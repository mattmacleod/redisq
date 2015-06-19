require 'securerandom'
require 'json'

class Redisq
  class Item
    class InvalidItemError < RuntimeError; end

    attr_reader :payload, :id

    def initialize(payload, id: nil)
      @payload = payload
      @id = id || SecureRandom.uuid
    end

    def self.from_json(json)
      data = JSON.load(json)
      fail InvalidItemError unless data.has_key?('id') && data.has_key?('payload')

      new(data['payload'], id: data['id'])
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
  end
end
