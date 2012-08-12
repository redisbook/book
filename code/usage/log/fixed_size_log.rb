require 'redis'

LENGTH = 4

$redis = Redis.new

def write(category, content)
    raise "Content's length must equal to #{LENGTH}" unless content.length == LENGTH 
    return $redis.append(category, content)
end

def read(category, n)
    return $redis.getrange(category, n*LENGTH, (n+1)*LENGTH-1)
end

def read_all(category)
    all_log = $redis.get(category)
    total_log_length = count(category)

    arr = Array.new
    i = 0
    while i < total_log_length do
        arr << all_log[i*LENGTH ... (i+1)*LENGTH]
        i += 1
    end
    
    return arr
end

def count(category)
    total_log_length = $redis.strlen(category)
    if total_log_length == 0
        return 0
    else
        return total_log_length / LENGTH
    end
end

def flush(category)
    return $redis.del(category)
end
