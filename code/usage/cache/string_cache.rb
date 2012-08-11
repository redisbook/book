require 'redis'

$redis = Redis.new

def set(key, value, timeout=nil)
    if timeout == nil
        return $redis.set(key, value)
    else
        return $redis.setex(key, timeout, value)
    end
end

def get(key)
    return $redis.get(key)
end
