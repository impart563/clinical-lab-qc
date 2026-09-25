///|
pub(all) enum AssessmentStatus {
  InControl
  Warning
  RequiresReview
  Incomplete
} derive(Eq, Debug)

///|
pub fn AssessmentStatus::name(self : AssessmentStatus) -> String {
  match self {
    InControl => "InControl"
    Warning => "Warning"
    RequiresReview => "RequiresReview"
    Incomplete => "Incomplete"
  }
}

///|
pub(all) enum RuleScope {
  SingleObservation
  SameRun
  ConsecutiveRuns
} derive(Eq, Debug)

///|
pub(all) enum Direction {
  Above
  Below
  SameSide
} derive(Eq, Debug)

///|
pub(all) enum InputIssueCode {
  InvalidProgram
  MissingRequiredControl
  UnknownControlLevel
  DuplicateControlPoint
  PrecisionMismatch
  InvalidEpoch
  InvalidRunId
  EpochSnapshotMismatch
  RepeatedEpoch
  DuplicateRunId
  NonIncreasingSequence
  ArithmeticOverflow
  CsvMalformed
  CsvHeader
  CsvPrecision
} derive(Eq, Debug)

///|
pub fn InputIssueCode::name(self : InputIssueCode) -> String {
  match self {
    InvalidProgram => "invalid_program"
    MissingRequiredControl => "missing_required_control"
    UnknownControlLevel => "unknown_control_level"
    DuplicateControlPoint => "duplicate_control_point"
    PrecisionMismatch => "precision_mismatch"
    InvalidEpoch => "invalid_epoch"
    InvalidRunId => "invalid_run_id"
    EpochSnapshotMismatch => "epoch_snapshot_mismatch"
    RepeatedEpoch => "repeated_epoch"
    DuplicateRunId => "duplicate_run_id"
    NonIncreasingSequence => "non_increasing_sequence"
    ArithmeticOverflow => "arithmetic_overflow"
    CsvMalformed => "csv_malformed"
    CsvHeader => "csv_header"
    CsvPrecision => "csv_precision"
  }
}

///|
pub(all) struct InputIssue {
  code : InputIssueCode
  run_id : String?
  message : String
} derive(Debug)

///|
pub(all) struct EvidencePoint {
  run_id : String
  epoch_id : String
  sequence : Int64
  timestamp : String
  control_level_id : String
  value : Int64
  precision : Int
  unit : String
  mean : Int64
  standard_deviation : Int64
  threshold : Int64
  direction : Direction
} derive(Debug)

///|
pub(all) struct RuleHit {
  rule : @assay.Rule
  scope : RuleScope
  evidence : Array[EvidencePoint]
  reason : String
} derive(Debug)

///|
pub(all) struct RunAssessment {
  run_id : String
  sequence : Int64
  status : AssessmentStatus
  hits : Array[RuleHit]
  input_issues : Array[InputIssue]
} derive(Debug)

///|
pub(all) struct Trajectory {
  assessments : Array[RunAssessment]
  input_issues : Array[InputIssue]
} derive(Debug)
