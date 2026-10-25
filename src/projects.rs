use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
#[derive(Default, Serialize, Deserialize)]
pub struct Projects {
    used: BTreeSet<u32>,
    pub visible: Vec<Project>,
}
#[derive(Serialize, Deserialize)]
pub struct Project {
    pub slot: u32,
    pub label: String,
    pub paths: BTreeSet<String>,
}
impl Projects {
    pub fn add(&mut self, label: String, exact: Option<u32>) -> anyhow::Result<u32> {
        let slot = if let Some(s) = exact {
            s
        } else {
            let mut s = 0;
            while self.used.contains(&s) {
                s += 1;
            }
            s
        };
        // An exact slot may restore a deleted (used but hidden) account.
        anyhow::ensure!(
            slot < crate::derivation::HARDENED
                && !self.visible.iter().any(|p| p.slot == slot)
                && (exact.is_some() || !self.used.contains(&slot))
                && valid_label(&label),
            "invalid project"
        );
        self.used.insert(slot);
        self.visible.push(Project {
            slot,
            label,
            paths: BTreeSet::new(),
        });
        Ok(slot)
    }
    pub fn rename(&mut self, slot: u32, label: String) -> anyhow::Result<()> {
        anyhow::ensure!(valid_label(&label), "invalid label");
        self.visible
            .iter_mut()
            .find(|p| p.slot == slot)
            .ok_or_else(|| anyhow::anyhow!("unknown project"))?
            .label = label;
        Ok(())
    }
    pub fn hide(&mut self, slot: u32) {
        self.visible.retain(|p| p.slot != slot);
    }
    /// Hides a visible project, refusing unknown slots and the last account.
    pub fn remove(&mut self, slot: u32) -> anyhow::Result<()> {
        anyhow::ensure!(
            self.visible.iter().any(|p| p.slot == slot),
            "unknown project"
        );
        anyhow::ensure!(self.visible.len() > 1, "cannot remove the last account");
        self.hide(slot);
        Ok(())
    }
    pub fn add_address(&mut self, slot: u32, exact: Option<u32>) -> anyhow::Result<String> {
        let p = self
            .visible
            .iter_mut()
            .find(|p| p.slot == slot)
            .ok_or_else(|| anyhow::anyhow!("unknown project"))?;
        let root = crate::derivation::root_path(slot)?;
        let mut index = exact.unwrap_or(0);
        if exact.is_none() {
            while p.paths.contains(&format!("{root}/{index}")) {
                index += 1;
            }
        }
        anyhow::ensure!(
            index < crate::derivation::HARDENED,
            "address index exhausted"
        );
        let path = format!("{root}/{index}");
        p.paths.insert(path.clone());
        Ok(path)
    }
}
impl Projects {
    /// Adds payment addresses the account's Payroof project handed out (children of
    /// its payment root), so they can be spent from like the account's own.
    pub fn add_payment_paths<'a>(
        &mut self,
        slot: u32,
        paths: impl IntoIterator<Item = &'a String>,
    ) -> anyhow::Result<()> {
        let root = crate::derivation::payment_root(slot)?;
        let p = self
            .visible
            .iter_mut()
            .find(|p| p.slot == slot)
            .ok_or_else(|| anyhow::anyhow!("unknown project"))?;
        for path in paths {
            crate::path_source::validate_child(&root, path)?;
            p.paths.insert(path.clone());
        }
        Ok(())
    }
}
fn valid_label(label: &str) -> bool {
    (1..=100).contains(&label.chars().count())
}
#[cfg(test)]
mod tests {
    use super::Projects;
    #[test]
    fn exact_slot_restores_a_removed_project_but_auto_skips_it() {
        let mut p = Projects::default();
        assert_eq!(p.add("A".into(), None).unwrap(), 0);
        assert_eq!(p.add("B".into(), None).unwrap(), 1);
        p.remove(0).unwrap();
        assert_eq!(p.add("C".into(), None).unwrap(), 2);
        assert!(p.add("dup".into(), Some(1)).is_err());
        assert_eq!(p.add("A again".into(), Some(0)).unwrap(), 0);
        assert!(p.add("dup".into(), Some(0)).is_err());
    }
    #[test]
    fn only_children_of_the_payment_root_are_added_as_payment_paths() {
        let mut p = Projects::default();
        p.add("A".into(), Some(3)).unwrap();
        let good = "m/44'/60'/3'/1/7".to_string();
        p.add_payment_paths(3, [&good]).unwrap();
        assert!(p.visible[0].paths.contains(&good));
        for bad in ["m/44'/60'/3'/0/7", "m/44'/60'/4'/1/7", "m/44'/60'/3'/1/7/0"] {
            assert!(p.add_payment_paths(3, [&bad.to_string()]).is_err(), "{bad}");
        }
        assert!(p.add_payment_paths(9, [&good]).is_err());
    }
    #[test]
    fn remove_refuses_unknown_and_last() {
        let mut p = Projects::default();
        p.add("A".into(), None).unwrap();
        assert!(p.remove(0).is_err());
        p.add("B".into(), None).unwrap();
        assert!(p.remove(9).is_err());
        p.remove(0).unwrap();
        assert!(p.remove(1).is_err());
    }
}
