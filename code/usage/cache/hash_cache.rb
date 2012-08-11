require 'redis'

$redis = Redis.new

def set(hash_name, key, value)
    return $redis.hset(hash_name, key, value)
end

def get(hash_name, key)
    return $redis.hget(hash_name, key)
end

def expire(hash_name, timeout)
    return $redis.expire(hash_name, timeout)
end
