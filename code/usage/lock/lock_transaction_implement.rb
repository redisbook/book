# coding: utf-8

require "redis"

$redis = Redis.new

def acquire(key, timeout, uid)

    $redis.watch(key)

    # 已经被其他客户端加锁？
    if $redis.exists(key)
        $redis.unwatch
        return false
    end

    # 尝试加锁
    result = $redis.multi do |t|
        t.setex(key, timeout, uid)
    end

    # 加锁成功？
    return result != nil

end

def release(key, uid)

    $redis.watch(key)

    # 锁不存在或已经释放？
    if $redis.exists(key) == false
        $redis.unwatch
        return true
    end

    # 比对 uid ，如果匹配就删除 key
    if uid == $redis.get(key)
        result = $redis.multi do |t|
            t.del(key)
        end
        # 删除成功？
        return result != nil
    else
        return false
    end

end
