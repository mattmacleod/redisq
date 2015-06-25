require 'securerandom'
require 'json'

class Redisq
  class Item
    class InvalidItemError < RuntimeError; end

    attr_reader :payload, :id, :queue

    def initialize(payload, id: nil, queue:)
      @payload = payload
      @queue = queue
      @id = id || SecureRandom.uuid
    end

    def self.from_json(json, queue:)
      data = JSON.load(json)
      fail InvalidItemError unless data.key?('id') && data.key?('payload')

      new(data['payload'], id: data['id'], queue: queue)
    end

    def as_json
      {
        id: id,
        payload: payload
      }
    end

    def to_json
      JSON.dump(as_json)
    end

    def inspect
      format(
        "<%s:0x%x id=\"%s\" payload=\"%s\">",
        self.class.name,
        object_id,
        id,
        payload
      )
    end
  end
end

require_relative 'processing_item'
