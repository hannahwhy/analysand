require 'couchdb/database'
require 'pathname'

module Couchdb
  ##
  # Methods for seeding a CouchDB database.
  #
  # Given a database DB, seed documents for DB are stored in
  #
  #     #{root}/db/DB/
  #
  # where root defaults -- and SHOULD point -- to Rails.root, but can be
  # overridden for e.g. testing.
  #
  # This module contains methods to seed all documents or just design
  # documents.  A synopsis follows.
  #
  # Common tasks
  # ============
  #
  # The below examples assume that you have an object with these methods:
  #
  #     seeder = Object.new
  #     seeder.extend Couchdb::Seeding
  #
  # Listing all seed documents for a database
  # -----------------------------------------
  #
  #     seeder.docs_for('site_development')  # see below re: environments
  #     # => [{"_id"=>"org.animemusicvideos.www:front_page", ...}, ...]
  #
  # If the database's name ends in
  #
  #     _#{Rails.env}
  #
  # that suffix will be stripped, and the result (in this case, "site") will
  # be used to locate seed documents for the database.
  #
  #
  # Listing all design documents for a database
  # -------------------------------------------
  #
  #     seeder.design_docs_for('site_development')
  #     # => [{"_id"=>"_design/page", ...}, ...]
  #
  #
  # Seeding documents for a database
  # --------------------------------
  #
  #     seeder.seed_docs('site_development')
  #     # => {"doc_id1"=>#<Response code=201 ...>, ...}
  #
  #
  # Seeding only design documents for a database
  # --------------------------------------------
  #
  #     seeder.seed_design_docs('site_development')
  #     # => {"_design/page"=>#<Response code=201 ...>, ...}
  #
  #
  # Update behavior
  # ===============
  #
  # Each document to be seeded will result in a GET and PUT on that document.
  # The first GET retrieves the current revision of the document; the PUT
  # replaces the document.
  #
  #
  # Load order
  # ==========
  #
  # When seeding both documents and design documents, documents will be loaded
  # in reverse lexicographical order by ID.  This permits documents to be
  # loaded without interference of e.g. authorization functions in
  # validate_doc_update keys, which may occur when other seeding procedures
  # are setting up user roles.
  module Seeding
    def docs_for(db_name)
      Dir["#{seed_dir_for(normalize_database_name(db_name))}/**/*.yml"].sort.reverse
    end

    def design_docs_for(db_name)
      Dir["#{seed_dir_for(normalize_database_name(db_name))}/_design/**/*.yml"]
    end

    def seed_docs(database_uri, credentials, &block)
      seed(method(:docs_for), database_uri, credentials, &block)
    end

    def seed_design_docs(database_uri, credentials, &block)
      seed(method(:design_docs_for), database_uri, credentials, &block)
    end

    def root
      Rails.root
    end

    private

    def seed(generator, database_uri, credentials, &block)
      db_name = normalize_database_name(database_uri.path.sub(%r{^/}, ''))
      db = Couchdb::Database.new(database_uri)

      generator.call(db_name).map do |fn|
        doc_id = doc_id_for(fn, db_name)
        doc = YAML.load(File.read(fn))

        resp = db.get(doc_id, credentials)
        rev = resp.body['_rev']

        doc.update('_rev' => rev) if rev

        db.put(doc_id, doc, credentials).tap do |resp|
          yield fn, doc_id, resp if block_given?
        end
      end
    end

    def normalize_database_name(db_name)
      db_name.sub(/_#{Rails.env}$/, '')
    end

    def doc_id_for(fn, db_name)
      seed_dir = Pathname.new(seed_dir_for(db_name))

      Pathname.new(fn).relative_path_from(seed_dir).to_s.sub(/\.yml$/, '')
    end

    def seed_dir_for(database_name)
      "#{root}/db/#{database_name}"
    end
  end
end

# vim:ts=2:sw=2:et:tw=78
