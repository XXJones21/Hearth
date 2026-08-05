//! Looks at a machine and decides what Hearth it can run.
//!
//! Three parts, deliberately separate:
//!
//!   scan()  -> Machine   what is physically here. Touches the machine.
//!   plan()  -> Plan      what it should run. PURE: same Machine plus same
//!                        Dictionary always yields the same Plan.
//!   fetch() -> ()        gets the bytes.
//!
//! The purity of `plan` is the point. It means the budget arithmetic, which is
//! where every downstream value comes from, is testable against fixtures rather
//! than needing four different computers.

pub mod dict;
pub mod download;
pub mod machine;
pub mod plan;

pub use dict::Dictionary;
pub use machine::{scan, Gpu, Machine};
pub use plan::{plan, Plan};

/// Bytes as a human reads them. GiB because that is what memory is measured in
/// and what a user comparing against their spec sheet expects.
pub fn human(bytes: u64) -> String {
    const GIB: f64 = 1_073_741_824.0;
    const MIB: f64 = 1_048_576.0;
    let b = bytes as f64;
    if b >= GIB {
        format!("{:.2} GB", b / GIB)
    } else {
        format!("{:.0} MB", b / MIB)
    }
}
