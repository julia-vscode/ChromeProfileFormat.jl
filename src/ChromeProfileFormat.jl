module ChromeProfileFormat

import JSON, Profile

function save_cpuprofile(filename, data, lidict)
    start_time = 386524903102 # TODO Come up with something better
    time_delta = 500

    script_ids = Dict{Symbol,Int}()
    next_script_id = 0

    node_ids = Dict{UInt,Int}()
    next_node_id = 1

    for i in unique(data)
        node_ids[i] = next_node_id
        next_node_id += 1
    end

    open(filename, "w") do f
        print(f, "{")

        JSON.print(f, "startTime")
        print(f, ":")
        
        JSON.print(f, start_time)

        print(f, ",")

        JSON.print(f, "endTime")
        print(f, ":")
        JSON.print(f, start_time + length(data) * time_delta)        

        print(f, ",")


        JSON.print(f, "nodes")
        print(f, ":[")
        
        for (i, (k, v)) in ((i, (k, lidict[k])) for (i,k) in enumerate(unique(data)))
            if i>1
                print(f, ",")
            end

            print(f, "{")

            JSON.print(f, "id")
            print(f, ":")
            JSON.print(f, node_ids[k])

            print(f, ",")

            JSON.print(f, "callFrame")
            print(f, ":")

            print(f, "{")

            JSON.print(f, "functionName")
            print(f, ":")
            JSON.print(f, v.func)

            print(f, ",")

            script_id = get(script_ids, v.file, -1)

            if script_id == -1
                script_id = next_script_id
                script_ids[v.file] = script_id
                next_script_id += 1
            end

            JSON.print(f, "scriptId")
            print(f, ":")
            JSON.print(f, string(script_id))

            print(f, ",")

            JSON.print(f, "url")
            print(f, ":")
            JSON.print(f, v.file)

            print(f, ",")

            # TODO I think this is wrong, because this probably now refers to a line in the function, not the definition of the function?
            JSON.print(f, "lineNumber")
            print(f, ":")
            JSON.print(f, v.line>0 ? v.line-1 : 0)

            print(f, ",")

            # TODO I think this is wrong, because this probably now refers to a line in the function, not the definition of the function?
            JSON.print(f, "columnNumber")
            print(f, ":")
            JSON.print(f, 0)

            print(f, "}")

            print(f, ",")

            JSON.print(f, "children")
            print(f, ":")
            JSON.print(f, Int[])

            print(f, "}")
        end
        print(f, "]")

        print(f, ",")

        JSON.print(f, "samples")
        print(f, ":")
        JSON.print(f, [node_ids[i] for i in data])

        print(f, ",")

        JSON.print(f, "timeDeltas")
        print(f, ":")
        JSON.print(f, fill(time_delta, length(data)))

        print(f, "}")
    end
end

end # module
