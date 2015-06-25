class Redisq
  class ProcessingQueue < Queue
    # ProcessingQueue#length requires a custom implementation, because it's
    # a sorted set rather than a list.
    def length
      connection.zcard(name)
    end
  end
end
