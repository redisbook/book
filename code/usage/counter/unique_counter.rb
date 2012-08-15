require 'redis'

$redis = Redis.new

def add(counter, member)
    return $redis.sadd(counter, member)
end

def remove(counter, member)
    return $redis.srem(counter, member)
end

def is_member?(counter ,member)
    return $redis.sismember(counter, member)
end

def members(counter)
    return $redis.members(counter)
end

def count(counter)
    return $redis.scard(counter)
end
