use std::{
    fs::{self},
    io::{self, Cursor, Read},
    path::Path,
};

#[cfg(windows)]
const BIN_DATA: &[u8] = include_bytes!("../data.bin");
#[cfg(not(windows))]
const BIN_DATA: &[u8] = &[];
// 4bytes
const LENGTH: usize = 4;
const IDENTIFIER_LENGTH: usize = 5;
const MD5_LENGTH: usize = 32;
const BUF_SIZE: usize = 4096;

pub(crate) struct BinaryData {
    pub md5_code: &'static [u8],
    // compressed gzip data
    pub raw: &'static [u8],
    pub path: String,
}

pub(crate) struct BinaryReader {
    pub files: Vec<BinaryData>,
    pub exe: String,
}

impl Default for BinaryReader {
    fn default() -> Self {
        let (files, exe) = BinaryReader::read();
        Self { files, exe }
    }
}

impl BinaryData {
    fn decompress(&self) -> io::Result<Vec<u8>> {
        let cursor = Cursor::new(self.raw);
        let mut decoder = brotli::Decompressor::new(cursor, BUF_SIZE);
        let mut buf = Vec::new();
        decoder.read_to_end(&mut buf)?;
        Ok(buf)
    }

    fn matches_file(&self, prefix: &Path) -> bool {
        let Ok(content) = fs::read(prefix.join(&self.path)) else {
            return false;
        };
        format!("{:x}", md5::compute(content)) == String::from_utf8_lossy(self.md5_code)
    }

    pub fn write_to_file(&self, prefix: &Path) -> io::Result<()> {
        let p = prefix.join(&self.path);
        if let Some(parent) = p.parent() {
            fs::create_dir_all(parent)?;
        }
        if self.matches_file(prefix) {
            return Ok(());
        }
        let content = self.decompress()?;
        let expected = String::from_utf8_lossy(self.md5_code);
        if format!("{:x}", md5::compute(&content)) != expected {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!("embedded file checksum mismatch: {}", self.path),
            ));
        }
        fs::write(p, content)
    }
}

impl BinaryReader {
    pub fn package_id(&self) -> String {
        let mut context = md5::Context::new();
        for file in &self.files {
            context.consume(file.path.as_bytes());
            context.consume(file.md5_code);
        }
        context.consume(self.exe.as_bytes());
        format!("{:x}", context.compute())
    }

    pub fn files_match(&self, prefix: &Path) -> bool {
        self.files.iter().all(|file| file.matches_file(prefix))
    }

    fn read() -> (Vec<BinaryData>, String) {
        let mut base: usize = 0;
        let mut parsed = vec![];
        assert!(BIN_DATA.len() > IDENTIFIER_LENGTH, "bin data invalid!");
        let mut iden = String::from_utf8_lossy(&BIN_DATA[base..base + IDENTIFIER_LENGTH]);
        if iden != "LDESK" {
            panic!("bin file is not valid!");
        }
        base += IDENTIFIER_LENGTH;
        loop {
            iden = String::from_utf8_lossy(&BIN_DATA[base..base + IDENTIFIER_LENGTH]);
            if iden == "LDESK" {
                base += IDENTIFIER_LENGTH;
                break;
            }
            // start reading
            let mut offset = 0;
            let path_length = u32::from_be_bytes([
                BIN_DATA[base + offset],
                BIN_DATA[base + offset + 1],
                BIN_DATA[base + offset + 2],
                BIN_DATA[base + offset + 3],
            ]) as usize;
            offset += LENGTH;
            let path =
                String::from_utf8_lossy(&BIN_DATA[base + offset..base + offset + path_length])
                    .to_string();
            offset += path_length;
            // file sz
            let file_length = u32::from_be_bytes([
                BIN_DATA[base + offset],
                BIN_DATA[base + offset + 1],
                BIN_DATA[base + offset + 2],
                BIN_DATA[base + offset + 3],
            ]) as usize;
            offset += LENGTH;
            let raw = &BIN_DATA[base + offset..base + offset + file_length];
            offset += file_length;
            // md5
            let md5 = &BIN_DATA[base + offset..base + offset + MD5_LENGTH];
            offset += MD5_LENGTH;
            parsed.push(BinaryData {
                md5_code: md5,
                raw: raw,
                path: path,
            });
            base += offset;
        }
        // executable
        let executable = String::from_utf8_lossy(&BIN_DATA[base..]).to_string();
        (parsed, executable)
    }

    #[cfg(linux)]
    pub fn configure_permission(&self, prefix: &Path) {
        use std::os::unix::prelude::PermissionsExt;

        let exe_path = prefix.join(&self.exe);
        if exe_path.exists() {
            if let Ok(f) = File::open(exe_path) {
                if let Ok(meta) = f.metadata() {
                    let mut permissions = meta.permissions();
                    permissions.set_mode(0o755);
                    f.set_permissions(permissions).ok();
                }
            }
        }
    }
}
