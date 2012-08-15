require 'redis'

$redis = Redis.new

def incr(counter, increment=1)
    return $redis.incrby(counter, increment)
end

def decr(counter, decrement=1)
    return $redis.decrby(counter, decrement)
end

def get(counter)
    value = $redis.get(counter)
    return value.to_i if value != nil
end

def reset(counter)
    value = $redis.set(counter, 0)
    return 0 if value == "OK"
end
