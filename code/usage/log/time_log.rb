require 'redis'

$redis = Redis.new

def write(category, content)
    return $redis.zadd(category, Time.now.to_f, content)
end

def read(category, n)
    return $redis.zrange(category, n, n, :with_scores => true)
end

def read_all(category)
    return $redis.zrange(category, 0, -1, :with_scores => true)
end

def count(category)
    return $redis.zcard(category)
end

def flush(category)
    return $redis.del(category)
end
