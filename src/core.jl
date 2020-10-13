mutable struct CallFrame
    functionName::String
    scriptId::String # unique script identifier
    url::String
    lineNumber::Int64
    columnNumber::Int64
end

struct PositionTickInfo
    line::Int64
    ticks::Int64
end

"""
    ProfileNode

A `ProfileNode` represents a method in the call-graph. Each child in `children`
is a callee and the `positionTicks` represents the location.
"""
mutable struct ProfileNode
    id::Int64
    callFrame::CallFrame
    hitCount::Int64 
    children::Vector{Int64}
    positionTicks::Vector{PositionTickInfo}
end

function enter!(node::ProfileNode, line)
    idx = findfirst(tick->tick.line == line, node.positionTicks)
    if idx === nothing
        push!(node.positionTicks, PositionTickInfo(line, 1))
    else
        old = node.positionTicks[idx]
        node.positionTicks[idx] = PositionTickInfo(line, old.ticks + 1)
    end
end

struct CPUProfile
    nodes::Vector{ProfileNode}
    startTime::Int64
    endTime::Int64
    samples::Vector{Int64}
    timeDeltas::Vector{Int64}
end

"""
    CPUProfile(data, period)

Fetches the collected `Profile` data.

# Arguments:
- `data::Vector{UInt}`: The data provided by `Profile.fetch` [optional].
- `period::UInt64`: The sampling period in nanoseconds [optional].
"""

function CPUProfile(data::Union{Nothing, Vector{UInt}} = nothing,
                    period::Union{Nothing, UInt64} = nothing; from_c = false)
    if data === nothing
        data = copy(Profile.fetch())
    end
    lookup = Profile.getdict(data)
    if period === nothing
        period = ccall(:jl_profile_delay_nsec, UInt64, ())
    end

    period = period ÷ 1000 # ns to ms

    methods = Dict{Tuple{String, Int64}, CallFrame}()
    function get_callframe!(url, start_line, name, file)
        get!(methods, (url, start_line)) do
            CallFrame(name, file, url, start_line, 0)
        end
    end

    nodes = ProfileNode[]
    function insert_node!(callframe)
        node = ProfileNode(length(nodes) + 1, callframe, 0, Int64[], [])
        push!(nodes, node)
        return node
    end

    samples    = Int64[] #  Ids of samples leaf.
    toplevel   = Set{Int64}() #  Ids of samples top nodes.
    timeDeltas = Int64[] # Time intervals between adjacent samples in microseconds. The first delta is relative to the profile startTime.

    # start decoding backtraces
    lastwaszero = true
    current = nothing

    # data is in bottom-up order therefore reverse it
    for ip in Iterators.reverse(data)
        # ip == 0x0 is the sentinel value for finishing a backtrace, therefore finising a sample
        if ip == 0
            # Avoid creating empty samples
            if lastwaszero
                @assert current === nothing
                continue
            end
            lastwaszero = true

            if current !== nothing
                push!(samples, current.id)
                push!(timeDeltas, period)
            end

            current = nothing
            continue
        end
        lastwaszero = false

        # A backtrace consists of a set of IP (Instruction Pointers), each IP points
        # a single line of code and `litrace` has the necessary information to decode
        # that IP to a specific frame (or set of frames, if inlining occured).

        # decode the inlining frames
        for frame in Iterators.reverse(lookup[ip])
            # ip 0 is reserved
            frame.pointer == 0 && continue
            frame.from_c && !from_c && continue

            # A `frame` is an entry in a backtrace. A `ProfileNode` is a method in the call-graph
            # which can be hit by multiple frames. So first we need to go from frame to method.
            # As keys we will use `url` + `start_line`.
            if frame.linfo === nothing # inlined frame
                file = string(frame.file)
                name = string(frame.func)
                start_line = convert(Int64, frame.line) # TODO: Get start_line properly
            else
                if frame.linfo isa Core.MethodInstance
                    linfo = frame.linfo::Core.MethodInstance
                elseif frame.linfo isa Core.CodeInfo
                    # TODO: stackframes.jl describes this as a top-level frame
                    linfo = frame.linfo.parent::Core.MethodInstance
                end
                meth       = linfo.def
                file       = string(meth.file)
                name       = string(meth.module, ".", meth.name)
                start_line = convert(Int64, meth.line)
            end
            # TODO: Deal with unkown or unresolved functions
            url = Base.find_source_file(file)
            if url === nothing
                url = file
            end

            # We use callframe as a identifier
            callframe = get_callframe!(url, start_line, name, file)

            node = nothing
            if current === nothing # top-level
                # have we seen this callframe before?
                for id in toplevel
                    if nodes[id].callFrame === callframe
                        node = nodes[id]
                    end
                end
                if node === nothing
                    node = insert_node!(callframe)
                end
                node.hitCount += 1
                push!(toplevel, node.id)

            else
                # is this callframe present in our parent?
                for id in current.children
                    if nodes[id].callFrame === callframe
                        node = nodes[id]
                    end
                end
                if node === nothing
                    node = insert_node!(callframe)
                    push!(current.children, node.id)
                end
            end
            # mark the new line as hit
            enter!(node, frame.line)
            current = node
        end
    end

    if current !== nothing
        push!(samples, current.id)
        push!(timeDeltas, period)
    end

    start_time = 0
    timeDeltas[1] = 0
    @assert length(timeDeltas) == length(samples)
    return CPUProfile(nodes, start_time, start_time + sum(timeDeltas), samples, timeDeltas) 
end

function save_cpuprofile(io::IO, data::Union{Nothing, Vector{UInt}} = nothing,
                         period::Union{Nothing, UInt64} = nothing; kwargs...)

    profile = CPUProfile(data, period; kwargs...)
    write(io, '{')
    JSON.print(io, "nodes")
    write(io, ':')
    write(io, '[')
    for (i, node) in enumerate(profile.nodes)
        write(io, '{')
        JSON.print(io, "id")
        write(io, ':')
        JSON.print(io, node.id)
        write(io, ',')
        JSON.print(io, "callFrame")
        write(io, ':')
        write(io, '{')
            JSON.print(io, "functionName")
            write(io, ':')
            JSON.print(io, node.callFrame.functionName)
            write(io, ',')
            JSON.print(io, "scriptId")
            write(io, ':')
            JSON.print(io, node.callFrame.scriptId)
            write(io, ',')
            JSON.print(io, "url")
            write(io, ':')
            JSON.print(io, node.callFrame.url)
            write(io, ',')
            JSON.print(io, "lineNumber")
            write(io, ':')
            JSON.print(io, node.callFrame.lineNumber)
            write(io, ',')
            JSON.print(io, "columnNumber")
            write(io, ':')
            JSON.print(io, node.callFrame.columnNumber)
        write(io, '}')
        write(io, ',')
        JSON.print(io, "hitCount")
        write(io, ':')
        JSON.print(io, node.hitCount)
        write(io, ',')
        JSON.print(io, "children")
        write(io, ':')
        JSON.print(io, node.children)
        write(io, ',')
        JSON.print(io, "positionTicks")
        write(io, ':')
        write(io, '[')
        for (j, tick) in enumerate(node.positionTicks)
            write(io, '{')
            JSON.print(io, "line")
            write(io, ':')
            JSON.print(io, tick.line)
            write(io, ',')
            JSON.print(io, "ticks")
            write(io, ':')
            JSON.print(io, tick.ticks)
            write(io, '}')
            j == length(node.positionTicks) || write(io, ',')
        end
        write(io, ']')
        write(io, '}')
        i == length(profile.nodes) || write(io, ',')
    end
    write(io, ']')
    write(io, ',')
    JSON.print(io, "startTime")
    write(io, ':')
    JSON.print(io, profile.startTime)
    write(io, ',')
    JSON.print(io, "endTime")
    write(io, ':')
    JSON.print(io, profile.endTime)
    write(io, ',')
    JSON.print(io, "samples")
    write(io, ':')
    JSON.print(io, profile.samples)
    write(io, ',')
    JSON.print(io, "timeDeltas")
    write(io, ':')
    JSON.print(io, profile.timeDeltas)
    write(io, '}')
    nothing
end

function save_cpuprofile(filename::AbstractString, data::Union{Nothing, Vector{UInt}} = nothing,
    period::Union{Nothing, UInt64} = nothing; kwargs...)

    open(filename, "w") do io
        save_cpuprofile(io, data, period; kwargs...)
    end
end
