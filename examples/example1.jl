using Profile, ChromeProfileFormat

function foo()
    A = randn(1000, 1000)

    return inv(A)
end

foo()
Profile.clear()
@profile foo()

ChromeProfileFormat.save_cpuprofile("test.cpuprofile", from_c=true)
