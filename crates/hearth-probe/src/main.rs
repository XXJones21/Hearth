//! hearth-probe: look at this machine, decide what Hearth it can run.

use anyhow::{bail, Result};
use clap::{Parser, Subcommand};
use hearth_probe::dict::hf_url;
use hearth_probe::{download, human, machine, plan, Dictionary, Machine};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "hearth-probe", version, about = "Decide what Hearth this machine can run.")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Look at this machine and print what is here.
    Scan,
    /// Decide what to run. Pure: give it a scan and it never touches hardware.
    Plan(Common),
    /// The same decision, as prose a person would read.
    Explain(Common),
    /// Check that every file in the dictionary actually resolves.
    Verify {
        #[arg(long)]
        dictionary: Option<PathBuf>,
    },
    /// Fetch what the plan asks for.
    Download {
        #[command(flatten)]
        common: Common,
        /// Where the weights land.
        #[arg(long)]
        dest: PathBuf,
        /// Check the URL resolves and stop, without pulling gigabytes.
        #[arg(long)]
        dry_run: bool,
    },
    /// List the machines that can be simulated.
    Fixtures,
}

#[derive(Parser, Clone)]
struct Common {
    /// Replay a captured machine instead of looking at this one.
    #[arg(long)]
    scan: Option<PathBuf>,
    /// Pretend to be one of the built-in machines. See `fixtures`.
    #[arg(long)]
    simulate: Option<String>,
    /// Use a different tier table.
    #[arg(long)]
    dictionary: Option<PathBuf>,
}

fn resolve(c: &Common) -> Result<Machine> {
    if let Some(name) = &c.simulate {
        return machine::simulated(name)
            .ok_or_else(|| anyhow::anyhow!("no such fixture '{}'. Try `fixtures`.", name));
    }
    if let Some(p) = &c.scan {
        let text = std::fs::read_to_string(p)?;
        return Ok(serde_json::from_str(&text)?);
    }
    machine::scan()
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.cmd {
        Cmd::Fixtures => {
            println!("Machines this can pretend to be:");
            for f in machine::FIXTURES {
                println!("  {}", f);
            }
        }

        Cmd::Scan => {
            let m = machine::scan()?;
            println!("{}", serde_json::to_string_pretty(&m)?);
        }

        Cmd::Plan(c) => {
            let m = resolve(&c)?;
            let d = Dictionary::or_embedded(c.dictionary.as_deref())?;
            match plan(&m, &d) {
                Ok(p) => println!("{}", serde_json::to_string_pretty(&p)?),
                Err(e) => {
                    eprintln!("{}", e);
                    std::process::exit(2);
                }
            }
        }

        Cmd::Explain(c) => {
            let m = resolve(&c)?;
            let d = Dictionary::or_embedded(c.dictionary.as_deref())?;
            explain(&m, &d)?;
        }

        Cmd::Verify { dictionary } => {
            let d = Dictionary::or_embedded(dictionary.as_deref())?;
            let mut bad = 0;
            let mut throttled = 0;
            println!("Checking every file in the dictionary resolves.\n");
            let mut first = true;
            for t in &d.tiers {
                for (kind, file, want) in std::iter::once(("preferred", t.file.clone(), t.bytes))
                    .chain(t.fallback.iter().map(|f| ("fallback ", f.file.clone(), f.bytes)))
                {
                    // Hugging Face rate-limits a burst of HEADs. Pace them.
                    if !first {
                        std::thread::sleep(std::time::Duration::from_millis(1200));
                    }
                    first = false;
                    let url = hf_url(&t.repo, &file);
                    match download::probe(&url) {
                        Ok((200, len)) => {
                            let note = match len {
                                Some(l) if l.abs_diff(want) > want / 20 => {
                                    format!("  SIZE DRIFT: server {}, dictionary {}", human(l), human(want))
                                }
                                Some(l) => format!("  {}", human(l)),
                                None => String::new(),
                            };
                            println!("  ok    tier {} {}  {}{}", t.id, kind, file, note);
                        }
                        // Rate limited, not wrong. Says nothing about the file.
                        Ok((429, _)) => {
                            throttled += 1;
                            println!("  ...   tier {} {}  {}  rate limited", t.id, kind, file);
                        }
                        Ok((code, _)) => {
                            bad += 1;
                            println!("  FAIL  tier {} {}  {}  HTTP {}", t.id, kind, file, code);
                        }
                        Err(e) => {
                            bad += 1;
                            println!("  FAIL  tier {} {}  {}  {}", t.id, kind, file, e);
                        }
                    }
                }
            }
            println!();
            if bad > 0 {
                bail!("{} file(s) in the dictionary do not resolve", bad);
            }
            if throttled > 0 {
                println!(
                    "{} file(s) could not be checked because Hugging Face rate limited us. \
                     Wait a minute and run again.",
                    throttled
                );
            } else {
                println!("Every file resolves.");
            }
        }

        Cmd::Download { common, dest, dry_run } => {
            let m = resolve(&common)?;
            let d = Dictionary::or_embedded(common.dictionary.as_deref())?;
            let p = plan(&m, &d).map_err(|e| anyhow::anyhow!("{}", e))?;

            println!("Plan: {} ({}), {} to download.\n", p.model, p.quant, human(p.total_download_bytes));
            for item in &p.downloads {
                let Some(url) = &item.url else {
                    println!("{}: fetched by the runtime on first use, skipping here.\n", item.what);
                    continue;
                };
                println!("{} [{}]", item.what, human(item.bytes));
                println!("  {}", url);
                if dry_run {
                    match download::probe(url)? {
                        (200, len) => println!(
                            "  resolves, server says {}\n",
                            len.map(human).unwrap_or_else(|| "unknown size".into())
                        ),
                        (code, _) => println!("  HTTP {}\n", code),
                    }
                    continue;
                }
                let file = item.file.clone().unwrap_or_else(|| "download.bin".into());
                let out = dest.join(&file);
                download::fetch_verified(url, &out, Some(item.bytes), item.sha256.as_deref(), &mut |_, _| {})?;
                if item.sha256.is_some() {
                    println!("  sha256 verified");
                }
                println!("  -> {}\n", out.display());
            }
        }
    }
    Ok(())
}

fn explain(m: &Machine, d: &Dictionary) -> Result<()> {
    let gpu = m
        .gpu
        .as_ref()
        .map(|g| {
            let mem = g
                .vram_bytes
                .map(|v| format!(", {}", human(v)))
                .unwrap_or_else(|| format!(", {} shared", human(m.ram_bytes)));
            format!("{}{}", g.name, mem)
        })
        .unwrap_or_else(|| "no supported graphics card".into());

    println!("This machine");
    println!("  {} on {}", gpu, m.os);
    println!("  {} of memory, {} free on disk", human(m.ram_bytes), human(m.free_disk_bytes));
    if let Some(sim) = &m.simulated {
        println!("  (simulated: {})", sim);
    }
    println!();

    let p = match plan(m, d) {
        Ok(p) => p,
        Err(e) => {
            println!("{}", e);
            std::process::exit(2);
        }
    };

    println!("What it should run");
    println!("  {}  [{}]", p.model, p.label);
    println!("  {}", p.note);
    println!("  {}/{}", p.repo, p.file);
    println!();
    println!("  context      {} tokens", p.n_ctx);
    println!("  backend      {}", p.backend);
    println!("  coexistence  {}", if p.coexist { "mind and voice together" } else { "one at a time" });
    if let Some(a) = &p.cuda_arch {
        println!("  cuda arch    {}", a);
    }
    println!();

    println!("Download");
    for x in &p.downloads {
        println!("  {:<22} {}", x.what, human(x.bytes));
    }
    println!("  {:<22} {}", "total", human(p.total_download_bytes));
    println!();

    println!("Why");
    for r in &p.reasons {
        println!("  - {}", r);
    }
    if !p.warnings.is_empty() {
        println!();
        println!("Worth knowing");
        for w in &p.warnings {
            println!("  ! {}", w);
        }
    }
    Ok(())
}
