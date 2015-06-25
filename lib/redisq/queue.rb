class Redisq
  class Queue
    attr_reader :name, :connection

    def initialize(name, connection)
      @name = name
      @connection = connection
    end

    def any?
      length > 0
    end

    def length
      connection.llen(name)
    end

    def flush!
      connection.del(name)
    end
  end
end

require_relative 'source_queue'
require_relative 'processing_queue'
require_relative 'error_queue'
