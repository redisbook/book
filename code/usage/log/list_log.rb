require 'redis'

$redis = Redis.new

def write(category, content)
    return $redis.rpush(category, content)
end

def read(category, n)
    return $redis.lindex(category, n)
end

def read_all(category)
    return $redis.lrange(category, 0, -1)
end

def count(category)
    return $redis.llen(category)
end

def flush(category)
    return $redis.del(category)
end
