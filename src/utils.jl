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
