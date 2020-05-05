using Profile, ChromeProfileFormat

function foo()
    A = randn(1000, 1000)

    return inv(A)
end

foo()
Profile.clear()
@profile foo()

data, lines = Profile.retrieve()
data2, lines2 = Profile.flatten(data, lines)

ChromeProfileFormat.save_cpuprofile("test.cpuprofile", data2, lines2)
