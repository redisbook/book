# coding: utf-8

require "redis"

$redis = Redis.new

def acquire(key, timeout, uid)

    script = "
        if redis.call('exists', KEYS[1]) == 0 then
            return redis.call('setex', KEYS[1], ARGV[1], ARGV[2])
        end
    "

    return "OK" == $redis.eval(script, :keys => [key], :argv => [timeout, uid])

end

def release(key, uid)
    
    script = "
        if redis.call('get', KEYS[1]) == ARGV[1] then
            return redis.call('del', KEYS[1])
        end
    "

    return 1 == $redis.eval(script, :keys => [key], :argv => [uid])

end
