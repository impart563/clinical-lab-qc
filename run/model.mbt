///|
pub(all) struct ControlPoint {
  control_level_id : String
  value : Int64
  precision : Int
} derive(Debug)

///|
pub(all) struct QCRun {
  run_id : String
  epoch : @epoch.QCEpoch
  sequence : Int64
  timestamp : String
  observations : Array[ControlPoint]
} derive(Debug)

///|
pub extend ControlPoint with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend QCRun with @moonbitlang/core/debug.Debug::{to_repr}
