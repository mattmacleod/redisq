require 'redis'
require 'timeout'
require_relative 'redisq/item'
require_relative 'redisq/lua_script'

require 'pry'

class Redisq
  DEFAULT_PROCESSING_TIMEOUT = 60 * 60 # 1 hour
  TIMEOUT_FLUSH_PERIOD = 10 # Seconds

  attr_reader :queue_name

  attr_reader :scripts
  private :scripts

  def initialize(queue_name)
    @queue_name = queue_name
    @scripts = {}

    register_scripts
    run_timeout_thread
  end

  def connection
    @connection ||= Redis.new(uri: redis_uri)
  end

  def push(data)
    Item.new(data).tap do |item|
      exec_script(:push, argv: [item.to_json])
    end.id
  end

  def each(processing_timeout: DEFAULT_PROCESSING_TIMEOUT)
    loop do
      with_processing_queue(timeout: processing_timeout) do |item|
        yield(item)
      end
    end
  end

  def pop(processing_timeout: DEFAULT_PROCESSING_TIMEOUT)
    with_processing_queue(timeout: processing_timeout) do |item|
      return item
    end
  end

  def any?
    length > 0
  end

  def length
    connection.llen(queue_name)
  end

  def flush!
    connection.del(queue_name)
  end

  def flush_all!
    connection.del(queue_name, processing_queue_name, error_queue_name)
  end

  def errors
    fail "Not implemented"
  end

  def processing
    fail "Not implemented"
  end

  private

  def redis_uri
    'redis://localhost'
  end

  def processing_queue_name
    @processing_queue_name = "#{ queue_name }_processing"
  end

  def error_queue_name
    @error_queue_name = "#{ queue_name }_error"
  end

  def with_processing_queue(timeout:)
    flush_timeouts

    until data = try_pop(processing_timeout: timeout)
      wait_for_notification
    end

    Timeout.timeout(timeout) do
      yield Item.from_json(data)
    end
  end

  def wait_for_notification
    connection.subscribe(queue_name) do |on|
      unsubscribed = false

      on.message do
        connection.unsubscribe(queue_name) unless unsubscribed
        unsubscribed = true
      end
    end
  end

  def try_pop(processing_timeout:)
    timeout = Time.now.to_i + processing_timeout
    exec_script(:pop, argv: [timeout])
  end

  def flush_timeouts
    exec_script(:expire, argv: [Time.now.to_i])
  end

  def register_scripts
    build_scripts

    scripts.each do |_, script|
      connection.script(:LOAD, script.content)
    end
  end

  def exec_script(name, keys: [], argv: [])
    connection.evalsha(
      scripts[name].sha,
      keys: keys,
      argv: argv
    )
  end

  def build_scripts
    params = {
      source_queue: queue_name,
      processing_queue: processing_queue_name,
      error_queue: error_queue_name
    }

    LuaScript::SCRIPTS.each do |name|
      scripts[name] = LuaScript.new(name, params)
    end
  end

  def run_timeout_thread
    Thread.new do
      loop do
        flush_timeouts
        sleep(TIMEOUT_FLUSH_PERIOD)
      end
    end
  end
end
