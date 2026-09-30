///|
pub(all) struct QCEpoch {
  id : String
  reagent_lot : String
  control_lot : String
  calibration_id : String
  program_version : String
} derive(Debug)

///|
pub extend QCEpoch with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn QCEpoch::has_same_metadata(self : QCEpoch, other : QCEpoch) -> Bool {
  self.id == other.id &&
  self.reagent_lot == other.reagent_lot &&
  self.control_lot == other.control_lot &&
  self.calibration_id == other.calibration_id &&
  self.program_version == other.program_version
}

///|
pub fn QCEpoch::is_valid(self : QCEpoch) -> Bool {
  !self.id.trim().is_empty() &&
  !self.reagent_lot.trim().is_empty() &&
  !self.control_lot.trim().is_empty() &&
  !self.calibration_id.trim().is_empty() &&
  !self.program_version.trim().is_empty()
}
