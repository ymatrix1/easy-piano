//! Score import bridge (docs/specs/score-import-and-page-view.md section 2.1).
//! Parsing and conversion live in `easy_piano_core::score_import`; this file only adapts types.

use easy_piano_core::score_import::song::import_song_json;

/// Imports a score file (MusicXML, MXL, MIDI, ABC or LilyPond) and returns it as a
/// content song JSON (docs/specs/content-format.md), ready for the practice session.
pub fn import_score(file_name: String, data: Vec<u8>) -> Result<String, String> {
    import_song_json(&file_name, &data)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn imports_abc_as_song_json() {
        let abc = b"X:1\nT:Scale\nM:4/4\nL:1/4\nK:C\nCDEF|\n";
        let json = import_score("scale.abc".into(), abc.to_vec()).unwrap();
        assert!(json.contains(r#""RH":"C4:4 D4:4 E4:4 F4:4""#), "{json}");
    }

    #[test]
    fn rejects_unknown_extension() {
        assert!(import_score("song.pdf".into(), Vec::new()).is_err());
    }
}
