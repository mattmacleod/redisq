# Redisq

Implements a [reliable queue using Redis](http://redis.io/commands/rpoplpush#pattern-reliable-queue)
in an easy-to-use gem.

## Use cases

[Sidekiq](http://www.sidekiq.org) is awesome, but it can be heavyweight when
looking for a simple blocking, reliable queueing system that can communicate
between different applications.

Redisq also offers reliable queueing (within the constraints that Redis is
reliable) and provides simple recovery of failed items.


## Usage

- Create a new queue using `Redisq.new(queue_name)`
- Push items on to the queue using `#push` - e.g. `queue.push('Test data')`
- Consume items from the queue using `#each`, which will block forever until an item is available, and yield the item
- Consume a single item using `#pop`, which will block until an item is available

### Basic usage 
```ruby
require 'redisq'

queue = Redisq.new('test_queue')
queue.push('Process me')
#=> '42C6C18D-9417-46D9-A086-D21579A37787' # Each Redisq item is assigned a UUID

queue.each do |item|
  puts "I received an item with id #{ item.id }: #{ item.payload }"
  item.commit!
end

#=> "I received an item with id 42C6C18D-9417-46D9-A086-D21579A37787: Process me"
```

Items can be moved to an error queue by calling fail! – this will be implicitly
called if an exception is raised from within your processing block.

```ruby
queue.each do |item|
  # I just don't like this one
  item.fail!
end
```

Items can be rescheduled for processing by calling requeue!

```ruby
queue.each do |item|
  # I want to do this one later
  item.requeue!
end
```

Items must be explicitly commited, failed or requeued by your application code,
or it will be implicitly failed and the enumerator will raise an exception.

```ruby
queue.each do |item|
  # Not going to call item.commit!
end

#=> Redisq::DanglingItemException: did not explicitly finish processing item 621379B5-D0E3-45A2-89D4-94E0BEFA7EFC
```

Alternatively, you can pop a single item from the queue in a block

```ruby
queue.pop do |item|
  # Same semantics as #each, but only for one item.
end
```

### Inspecting and manipulating the queue
```ruby

queue.push('Process me')
#=> "B09CA45C-8D2E-45EB-B247-6A63CA01C957"

queue.any?
#=> true

queue.length
#=> 1

queue.flush!
#=> true

queue.length
#=> 0

queue.push('Process me')
#=> "77E68B09-23BC-4A56-9372-D26E73CFAD0C"

queue.pop
#=> <Redisq::ProcessingItem @id="77E68B09-23BC-4A56-9372-D26E73CFAD0C" @queued_at=2015-06-06 15:57:00 UTC @processing_at=2015-06-06 15:56:00 UTC @payload="Process me">
# Popping an item off of the queue still requires you to explicitly commit/fail/requeue it! Otherwise, it'll be automatically errored.
```

### Error handling

```ruby
queue.push('Process me')
#=> "B7D02F45-4ABB-4813-9B78-DBF9AF9AE1F6"

queue.pop do |item|
  raise "I don't like this item"
end

queue.errors.any?
#=> true

queue.errors.length
#=> 1

queue.errors.pop do |item|
  puts item
  #=> <Redisq::ErroredItem @id="B7D02F45-4ABB-4813-9B78-DBF9AF9AE1F6" @queued_at=2015-06-06 15:55:00 UTC @errored_at=2015-06-06 15:56:00 UTC @payload="Process me" @last_error="I don't like this item">

  # Push the item back into the queue
  item.requeue!
  #=> "B7D02F45-4ABB-4813-9B78-DBF9AF9AE1F6"

  # Or alternatively, destroy it forever
  item.destroy!
  #=> "B7D02F45-4ABB-4813-9B78-DBF9AF9AE1F6"
end

```

Errors are not automatically requeued, and it is up to your application to
inspect and requeue/destroy errored items as required.

### Application failures

I'm sure it won't happen, but maybe your application will exit before it
finished consuming an item from the queue.

```ruby
queue.push('Process me')
#=> "02E70222-678A-4A04-8565-6D053AE06559"

queue.pop do |item|
  exit!
end

# Oops, we exited before completing or raising!
```

When accessing the same queue, the item will be available

```ruby
queue.processing.length
#=> 1

queue.processing.pop do |item|
  puts item
  #=> <Redisq::ProcessingItem @id="02E70222-678A-4A04-8565-6D053AE06559" @queued_at=2015-06-06 15:55:00 UTC @processing_at=2015-06-06 15:56:00 UTC @payload="Process me">

  item.requeue!
  #=> "02E70222-678A-4A04-8565-6D053AE06559"
end
```

### Timeouts

Items which are popped off the queue for processing will be considered failed
after a default of 1 hour, after which they will be moved to the error queue.

```ruby
queue.pop do |item|
  # This item takes too long to process
  sleep(10.hours)
  do_something_with(item)
end

#...

queue.processing.any?
#=> false

queue.errors.any?
#=> true

```

You can override the timeout on calls to `#each` or `#pop`

```ruby
queue.pop(processing_timeout: 10.seconds) do |item|
  do_something_with(item)
end
```

There's no timeout option for how long a queue should wait for items to available
on the queue - use the stdlib's default `Timeout` class.

```ruby
require 'timeout'

Timeout.timeout(15) do
  queue.each do |item|
    # Nothing is being pushed to this queue
  end
end
#=> Timeout::Error: execution expired
```

### Accessing the underlying connection

```ruby
queue.connection
#=> Redis
```
