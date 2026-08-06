//! Getting the bytes.
//!
//! Resumable, because these are multi-gigabyte files on home connections and a
//! dropped download that starts over is how people give up on an install.

use anyhow::{bail, Context, Result};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::time::Instant;

use crate::human;

/// Downloads `url` to `dest`, resuming a partial file if one is there.
/// Writes to `<dest>.part` and renames on success, so a half file is never
/// mistaken for a whole one.
pub fn fetch(url: &str, dest: &Path, expected: Option<u64>) -> Result<PathBuf> {
    fetch_with(url, dest, expected, &mut |_, _| {})
}

/// As `fetch`, reporting `(done, total)` as it goes. The client renders a
/// progress bar from this; the CLI prints a line.
pub fn fetch_with(
    url: &str,
    dest: &Path,
    expected: Option<u64>,
    progress: &mut dyn FnMut(u64, u64),
) -> Result<PathBuf> {
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("create {}", parent.display()))?;
    }

    if dest.exists() {
        let have = dest.metadata()?.len();
        match expected {
            Some(want) if have != want => {
                println!(
                    "  present but wrong size ({} on disk, expected {}), fetching again",
                    human(have),
                    human(want)
                );
                fs::remove_file(dest)?;
            }
            _ => {
                println!("  already here: {} ({})", dest.display(), human(have));
                return Ok(dest.to_path_buf());
            }
        }
    }

    let part = dest.with_extension("part");
    let resume_from = part.metadata().map(|m| m.len()).unwrap_or(0);

    let client = reqwest::blocking::Client::builder()
        .timeout(None)
        .build()
        .context("build http client")?;
    let mut req = client.get(url);
    if resume_from > 0 {
        println!("  resuming from {}", human(resume_from));
        req = req.header("Range", format!("bytes={}-", resume_from));
    }

    let mut res = req.send().with_context(|| format!("GET {}", url))?;
    if !res.status().is_success() {
        bail!("{} returned HTTP {}", url, res.status());
    }

    let resumed = res.status().as_u16() == 206;
    let remaining = res.content_length().unwrap_or(0);
    let total = if resumed {
        resume_from + remaining
    } else {
        remaining
    };
    if !resumed && resume_from > 0 {
        // Server ignored the range. Start over rather than corrupt the file.
        println!("  server does not support resume, starting over");
    }

    let mut out = if resumed {
        let mut f = OpenOptions::new().append(true).open(&part)?;
        f.seek(SeekFrom::End(0))?;
        f
    } else {
        File::create(&part)?
    };

    let mut done = if resumed { resume_from } else { 0 };
    let mut buf = vec![0u8; 1024 * 256];
    let start = Instant::now();
    let mut last_print = 0u64;

    loop {
        let n = res.read(&mut buf).context("read response")?;
        if n == 0 {
            break;
        }
        out.write_all(&buf[..n]).context("write file")?;
        done += n as u64;
        progress(done, total);

        if done - last_print > 32 * 1024 * 1024 {
            last_print = done;
            let secs = start.elapsed().as_secs_f64().max(0.001);
            let rate = (done - if resumed { resume_from } else { 0 }) as f64 / secs;
            let pct = if total > 0 {
                format!("{:>5.1}%", done as f64 / total as f64 * 100.0)
            } else {
                "     ".into()
            };
            print!(
                "\r  {} {} of {} at {}/s      ",
                pct,
                human(done),
                human(total),
                human(rate as u64)
            );
            let _ = std::io::stdout().flush();
        }
    }
    out.flush()?;
    drop(out);
    println!("\r  {} in {:.0}s{:20}", human(done), start.elapsed().as_secs_f64(), "");

    if let Some(want) = expected {
        let got = part.metadata()?.len();
        if got != want {
            // Not fatal. The dictionary's sizes are recorded by hand and a
            // mismatch more often means the dictionary is stale than that the
            // download is broken. Say so and keep the file.
            println!(
                "  note: got {} but the dictionary says {}. The file is kept; the dictionary \
                 may need updating.",
                human(got),
                human(want)
            );
        }
    }

    fs::rename(&part, dest)
        .with_context(|| format!("rename {} -> {}", part.display(), dest.display()))?;
    Ok(dest.to_path_buf())
}

/// As `fetch_with`, then a sha256 check when the dictionary carries one.
///
/// The hash pass streams the finished file, reporting `(hashed, total)` through
/// the same progress callback so a screen can show it; a multi-gigabyte hash
/// takes long enough that silence reads as a hang. On mismatch the file is
/// DELETED and the fetch fails: a corrupt model that stays on disk would be
/// picked up as "already here" on the retry and never fetched clean.
pub fn fetch_verified(
    url: &str,
    dest: &Path,
    expected: Option<u64>,
    sha256: Option<&str>,
    progress: &mut dyn FnMut(u64, u64),
) -> Result<PathBuf> {
    let path = fetch_with(url, dest, expected, progress)?;
    if let Some(want) = sha256 {
        verify_sha256(&path, want, progress)?;
    }
    Ok(path)
}

/// Stream-hash `path` and compare against the expected hex sha256, reporting
/// `(hashed, total)` as it goes. On mismatch the file is DELETED and this
/// fails: a corrupt file left in place would be taken for "already here" on
/// the retry and never fetched clean.
pub fn verify_sha256(
    path: &Path,
    want: &str,
    progress: &mut dyn FnMut(u64, u64),
) -> Result<()> {
    use sha2::Digest;
    let total = path.metadata()?.len();
    let mut file = File::open(path).with_context(|| format!("open {}", path.display()))?;
    let mut hasher = sha2::Sha256::default();
    let mut buf = vec![0u8; 1024 * 1024];
    let mut hashed = 0u64;
    loop {
        let n = file.read(&mut buf).context("read for hash")?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
        hashed += n as u64;
        progress(hashed, total);
    }
    let got = format!("{:x}", hasher.finalize());
    let want = want.trim();
    if !got.eq_ignore_ascii_case(want) {
        fs::remove_file(path)
            .with_context(|| format!("remove corrupt {}", path.display()))?;
        bail!(
            "{} failed its integrity check (sha256 {} on disk, {} expected). The file was \
             removed; retry the download.",
            path.display(),
            &got[..12],
            &want[..12.min(want.len())]
        );
    }
    Ok(())
}

/// A HEAD, to prove a URL resolves without pulling gigabytes. This is what
/// verifies the dictionary's filenames are real.
pub fn probe(url: &str) -> Result<(u16, Option<u64>)> {
    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()?;
    let res = client.head(url).send().with_context(|| format!("HEAD {}", url))?;
    let len = res.content_length();
    Ok((res.status().as_u16(), len))
}
