require 'redis'
require 'timeout'

require_relative 'redisq/item'
require_relative 'redisq/queue'

require_relative 'redisq/lua_script'

require 'pry'

class Redisq
  DEFAULT_PROCESSING_TIMEOUT = 60 * 60 # 1 hour
  TIMEOUT_FLUSH_PERIOD = 10 # Seconds

  attr_reader :source_queue, :error_queue, :processing_queue
  attr_reader :notification_name

  attr_reader :scripts
  private :scripts

  class DanglingItemError < RuntimeError; end

  def initialize(queue_name)
    @source_queue = SourceQueue.new(queue_name, connection)
    @processing_queue = ProcessingQueue.new("#{ queue_name }_processing", connection)
    @error_queue = ErrorQueue.new("#{ queue_name }_error", connection)
    @notification_name = queue_name

    @scripts = {}

    register_scripts
    run_timeout_thread
  end

  def connection
    @connection ||= Redis.new(uri: redis_uri)
  end

  def push(data)
    Item.new(data, queue: source_queue).tap do |item|
      exec_script(:push, argv: [item.to_json])
    end.id
  end

  def each(processing_timeout: DEFAULT_PROCESSING_TIMEOUT)
    loop do
      with_processing_queue(timeout: processing_timeout) do |item|
        yield(item)
        fail DanglingItemError unless item.completed?
      end
    end
  end

  def pop(processing_timeout: DEFAULT_PROCESSING_TIMEOUT)
    with_processing_queue(timeout: processing_timeout) do |item|
      return item
    end
  end

  def length
    source_queue.length
  end

  def any?
    length > 0
  end

  def flush_all!
    connection.multi do
      source_queue.flush!
      processing_queue.flush!
      error_queue.flush!
    end

    true
  end

  private

  def redis_uri
    'redis://localhost'
  end

  def with_processing_queue(timeout:)
    expire_timed_out_items

    until data = consume_item_from_source(processing_timeout: timeout)
      wait_for_notification
    end

    # We don't need ot rescue a timeout error, because the item will be
    # automatically flushed from the queue..
    Timeout.timeout(timeout) do
      yield ProcessingItem.from_json(data, queue: processing_queue)
    end
  end

  # redis-rb has a pretty amazing bug that means a client can read stale data if
  # two pubsub messages are sent to the same channel in quick succession. We
  # have to work around this by tracking the state of our unsubscription, and
  # ensuring we don't issue two unsubscribe requests.
  def wait_for_notification
    connection.subscribe(notification_name) do |on|
      unsubscribed = false

      on.message do
        connection.unsubscribe(notification_name) unless unsubscribed
        unsubscribed = true
      end
    end
  end

  def consume_item_from_source(processing_timeout:)
    timeout = Time.now.to_i + processing_timeout
    exec_script(:pop, argv: [timeout])
  end

  def expire_timed_out_items
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
      source_queue: source_queue.name,
      processing_queue: processing_queue.name,
      error_queue: error_queue.name
    }

    LuaScript::SCRIPTS.each do |name|
      scripts[name] = LuaScript.new(name, params)
    end
  end

  def run_timeout_thread
    Thread.new do
      loop do
        expire_timed_out_items
        sleep(TIMEOUT_FLUSH_PERIOD)
      end
    end
  end
end
