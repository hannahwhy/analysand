require 'analysand/errors'
require 'json/stream'

module Analysand
  module ViewStreaming
    # Private: A wrapper around JSON::Stream::Parser that extracts data from a
    # CouchDB view document.
    class Builder
      attr_reader :offset
      attr_reader :total_rows

      # Rows constructed by the JSON parser that are ready for
      # StreamingViewResponse#each.
      attr_reader :staged_rows

      # JSON::Stream::Parser callback methods.
      CALLBACK_METHODS = %w(
        start_object end_object start_array end_array key value
      )

      # If we find a key in the toplevel view object that isn't one of these,
      # we raise UnexpectedViewKey.
      KNOWN_KEYS = %w(
        total_rows offset rows
      )

      def initialize
        @in_rows = false
        @parser = JSON::Stream::Parser.new
        @stack = []
        @staged_rows = []

        CALLBACK_METHODS.each { |name| @parser.send(name, &method(name)) }
      end

      def <<(data)
        @parser << data
      end

      def start_object
        # We don't need to do anything for the toplevel view object, so just
        # focus on the objects in rows.
        if @in_rows
          @stack.push ObjectNode.new
        end
      end

      def end_object
        if @in_rows
          # If the stack's empty and we've come to the end of an object, assume
          # we've exited the rows key.  Trailing keys are handled by
          # check_toplevel_key_validity.
          if @stack.empty?
            @in_rows = false
          else
            obj = @stack.pop.to_object

            # If obj was the only thing on the stack and we're processing rows,
            # then we've completed an object and need to stage it for the
            # object stream.
            if @stack.empty?
              staged_rows << obj
            else
              @stack.last << obj
            end
          end
        end
      end

      def start_array
        # If we're not in the rows array but "rows" was the last key we've
        # seen, then we're entering the rows array.  Otherwise, we're building
        # an array in a row.
        if !@in_rows && @stack.pop == 'rows'
          @in_rows = true
        elsif @in_rows
          @stack.push []
        end
      end

      def end_array
        if @in_rows
          obj = @stack.pop

          # If there's nothing on the row stack, it means that we've hit the
          # end of the rows array.
          if @stack.empty?
            @in_rows = false
          else
            @stack.last << obj
          end
        end
      end

      def key(k)
        if !@in_rows
          check_toplevel_key_validity(k)
          @stack.push k
        else
          @stack.last << k
        end
      end

      def value(v)
        if !@in_rows
          case @stack.pop
          when 'total_rows'; @total_rows = v
          when 'offset'; @offset = v
          end
        else
          @stack.last << v
        end
      end

      def check_toplevel_key_validity(k)
        if !KNOWN_KEYS.include?(k)
          raise UnexpectedViewKey, "Unexpected key #{k} in top-level view object"
        end
      end

      # Simplifies key/value pair construction.
      class ObjectNode
        def initialize
          @obj = {}
        end

        def to_object
          @obj
        end

        def <<(term)
          if !@key
            @key = term
          elsif @key
            @obj[@key] = term
            @key = nil
          end
        end
      end
    end
  end
end
