require 'redis'

$redis = Redis.new

def incr(hash, counter, increment=1)
    return $redis.hincrby(hash, counter, increment)
end

def decr(hash, counter, decrement=1)
    return $redis.hincrby(hash, counter, -decrement)
end

def get(hash, counter)
    value = $redis.hget(hash, counter)
    return value.to_i if value != nil
end

def reset(hash, counter)
    value = $redis.hset(hash, counter, 0)
    return 0
end
