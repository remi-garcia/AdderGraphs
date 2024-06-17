function read_hcub_output(s::String, C::Vector{Int})
    addergraph = AdderGraph(C)
    adders_str = split(s, "\n")
    for val in adders_str
        if isempty(val)
            continue
        end
        node_details = strip.(split(val, "="))
        input_details = strip.(split(node_details[2][7:(end-1)], ","))
        node_value = parse(Int, node_details[1])
        node_stage = parse(Int, input_details[4])
        node_input_shifts_str = split(input_details[3], "/")
        node_input_shifts = Vector{Int}([abs(parse(Int, node_input_shifts_str[i]))-1 for i in 1:2])
        node_inputs = Vector{Int}([parse(Int, input_details[1]), parse(Int, input_details[2])])
        node_subtraction = Vector{Bool}([('-' == node_input_shifts_str[i][1]) for i in 1:2])
        addernode_inputs = Vector{AdderNode}([get_addernodes_by_value(addergraph, node_inputs[i])[end] for i in 1:2])
        push_node!(addergraph,
            AdderNode(
                node_value,
                [InputEdge(addernode_inputs[i], node_input_shifts[i], node_subtraction[i]) for i in 1:2],
                node_stage
            )
        )
    end

    return addergraph
end