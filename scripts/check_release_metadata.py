#!/usr/bin/env python3
"""Validate current, now-archived beta DOI, ORCID and version metadata."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def orcid_valid(value):
    digits=value.replace("-","")
    if len(digits)!=16 or not digits[:15].isdigit():
        return False
    check=0
    for digit in digits[:15]:
        check=(check+int(digit))*2
    remainder=(12-check%11)%11
    return digits[-1]==("X" if remainder==10 else str(remainder))


def main():
    import yaml
    cff=yaml.safe_load((ROOT/"CITATION.cff").read_text(encoding="utf8"))
    toml=(ROOT/"fpm.toml").read_text(encoding="utf8")
    fpm_version=re.search(r'^version\s*=\s*"([^"]+)"',toml,re.M)
    assert fpm_version and cff["version"]==fpm_version.group(1)
    assert cff["cff-version"]=="1.2.0" and cff["type"]=="software"
    assert cff["license"]=="MIT" and len(cff["keywords"])>=5
    assert len(cff["abstract"])>=80
    orcid=cff["authors"][0]["orcid"]
    assert orcid=="https://orcid.org/0000-0003-0299-5745" and orcid_valid(orcid.split("/")[-1])
    # These identifiers were verified against the published Zenodo v2 record.
    # Update the mapping deliberately on a new release; do not carry a stale
    # previous-version DOI into a subsequent source snapshot.
    published_version_dois = {
        "2.0.0-beta.1": "10.5281/zenodo.23679426",
    }
    expected_doi = published_version_dois.get(cff["version"])
    assert expected_doi, "New software version needs independently confirmed DOI metadata"
    assert cff["doi"] == expected_doi, "Citation DOI does not match software version"
    assert str(cff["date-released"]) == "2026-10-27", "Release date mismatch"
    assert not (ROOT/".zenodo.json").exists(), "CITATION.cff remains canonical metadata"
    print("Citation valid: version, author ORCID, Zenodo DOI, release date and metadata.")



if __name__=="__main__":
    main()
