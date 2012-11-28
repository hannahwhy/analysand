require 'analysand'
require 'celluloid'
require 'spec_helper'

describe 'Analysand::Database from multiple threads' do
  let!(:db) { Analysand::Database.new(database_uri) }
  let!(:thread_count) { 32 }

  before(:all) do
    WebMock.disable!
  end

  after(:all) do
    WebMock.enable!
  end

  before do
    clean_databases!
  end

  it 'processes all PUTs' do
    threads = (0...thread_count).map do |i|
      Thread.new do
        sleep 1

        (0...10).each do |j|
          tag = 10 * i + j
          db.put(tag.to_s, { :num => tag }, member1_credentials)
        end
      end
    end

    threads.each(&:join)

    db.all_docs(:stream => true).count.should == thread_count * 10
  end

  it 'processes all GETs' do
    docs = []

    (thread_count * 10).times do |i|
      docs << { :_id => i.to_s, :num => i }
    end

    db.bulk_docs!(docs, member1_credentials)

    result = (0...thread_count).map do |i|
      Celluloid::Future.new do
        sleep 1
        (0...10).map do |j|
          tag = 10 * i + j
          db.get(tag.to_s, member1_credentials).body['num']
        end.inject(&:+)
      end
    end.map(&:value).inject(&:+)

    result.should == (0...thread_count * 10).inject(&:+)
  end
end
