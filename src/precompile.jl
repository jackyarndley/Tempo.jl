# Representative workloads only: common epoch conversion, prepared default conversion, and
# one prepared graph route. This avoids an all-pairs precompile matrix.
PrecompileTools.@setup_workload begin
    epoch = Epoch(1.0e8 + 0.25, TAI)
    prepared_builtin = prepare_time_conversion(TAI, TDB)

    custom_system = TimeSystem{Float64}()
    add_timescale!(custom_system, TT)
    add_timescale!(custom_system, TAI, offset_tt2tai; parent=TT, ftp=offset_tai2tt)
    add_timescale!(custom_system, GPS, offset_gps2tai; parent=TAI, ftp=offset_tai2gps)
    prepared_custom = prepare_time_conversion(custom_system, TT, GPS)

    PrecompileTools.@compile_workload begin
        convert(TDB, epoch)
        prepared_builtin(value(epoch))
        prepared_custom(value(epoch))
        DateTime(epoch)
    end
end
