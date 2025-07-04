function odd(number::Int)
    if number == 0
        return 0
    end
    while mod(number, 2) == 0
        number = div(number, 2)
    end
    return number
end


function log2odd(number::Int)
    return round(Int, log2(div(number, odd(number))))
end


function _compute_msb_lsb_from_msb_lsb(msb_lsb1::Tuple{Int, Int}, msb_lsb2::Tuple{Int, Int}, subtraction::Bool)
    msb1, lsb1 = msb_lsb1
    msb2, lsb2 = msb_lsb2
    return (max(msb1, msb2)+(subtraction ? 0 : (min(msb1, msb2) < max(lsb1, lsb2) ? 0 : 1)), min(lsb1, lsb2))
end


function _compute_value_from_inputs(inputs::Vector{InputEdge})
    return round(Int, sum((-1)^(is_negative(input_edge)) * get_input_addernode_value(input_edge) * 2.0^(get_input_shift(input_edge)) for input_edge in inputs))
end


function int2bin(number::Int)
    @assert number >= 0
    return reverse(digits(number, base=2))
end

function bin2csd!(vector_bin2csd::Vector{Int})
    @assert issubset(unique(vector_bin2csd), [-1,0,1])
    first_non_zero = 0
    for i in length(vector_bin2csd):-1:1
        if vector_bin2csd[i] != 0
            if first_non_zero == 0
                first_non_zero = i
            end
        elseif first_non_zero - i >= 2
            for j in (i+1):first_non_zero
                vector_bin2csd[j] = 0
            end
            vector_bin2csd[first_non_zero] = -1
            vector_bin2csd[i] = 1
            first_non_zero = i
        else
            first_non_zero = 0
        end
    end
    if first_non_zero > 1
        for j in 1:first_non_zero
            vector_bin2csd[j] = 0
        end
        vector_bin2csd[first_non_zero] = -1
        pushfirst!(vector_bin2csd, 1)
    end

    return vector_bin2csd
end

function bin2csd(vector_bin::Vector{Int})
    @assert issubset(unique(vector_bin), [-1,0,1])
    vector_csd = copy(vector_bin)
    return bin2csd!(vector_csd)
end

function int2csd(number::Int)
    return bin2csd!(int2bin(number))
end