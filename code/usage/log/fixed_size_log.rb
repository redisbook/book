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
    0.upto(total_log_length-1) do |i|
        arr << all_log[i*LENGTH ... (i+1)*LENGTH]
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
