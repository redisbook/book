load 'time_log.rb'

def recent(category, n)
    return $redis.zrevrange(category, 0, n-1, :with_scores => true)
end
