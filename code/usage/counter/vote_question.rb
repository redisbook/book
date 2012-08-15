load 'unique_counter.rb'

def vote_up(question_id, user_id)
    if voted?(question_id, user_id)
        raise "alread voted"
    end
    return add("question-vote-up #{question_id}", user_id)
end

def vote_down(question_id, user_id)
    if voted?(question_id, user_id)
        raise "alread voted"
    end
    return add("question-vote-down #{question_id}", user_id)
end

def voted?(question_id, user_id)
    return (is_member?("question-vote-up #{question_id}", user_id) or \
            is_member?("question-vote-down #{question_id}", user_id))
end

def count_vote_up(question_id)
    return count("question-vote-up #{question_id}")
end

def count_vote_down(question_id)
    return count("question-vote-down #{question_id}")
end
