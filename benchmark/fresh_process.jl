load_time = @elapsed @eval using Tempo

const FRESH_EPOCH = Tempo.Epoch(1.0e8 + 0.25, Tempo.TAI)
first_convert = @timed Tempo.convert(Tempo.TDB, FRESH_EPOCH)
first_prepare = @timed Tempo.prepare_time_conversion(Tempo.TAI, Tempo.TDB)
const FRESH_CONVERSION = first_prepare.value
first_prepared_evaluation = @timed FRESH_CONVERSION(Tempo.value(FRESH_EPOCH))

println("package_load_s=", load_time)
println(
    "first_convert_s=", first_convert.time,
    " bytes=", first_convert.bytes,
)
println(
    "first_prepare_s=", first_prepare.time,
    " bytes=", first_prepare.bytes,
)
println(
    "first_prepared_evaluation_s=", first_prepared_evaluation.time,
    " bytes=", first_prepared_evaluation.bytes,
)
