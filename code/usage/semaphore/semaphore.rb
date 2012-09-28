require "redis"

$redis = Redis.new

# 设置信号量的名字和数量
def init(name, size)
    item = [] << name
    all_item = item * size
    $redis.lpush(name, all_item)
end

# 获取一个信号量，成功返回一个非空元素，失败返回一个 nil 。
# 如果暂时没有信号量可用，则阻塞直到有其他客户端释放信号量，或者超过 timeout 为止
def acquire(name, timeout=0)
     $redis.blpop(name, timeout)
end

# 释放一个信号量
# 客户端程序应该保证，只有获取了信号量的客户端可以调用这个函数
def release(name)
    $redis.lpush(name, name)
end
