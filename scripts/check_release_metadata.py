#!/usr/bin/env python3
"""Validate Zenodo-ready CITATION.cff and version without inventing a DOI."""
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
    assert "doi" not in cff and not (ROOT/".zenodo.json").exists()
    print("Citation valid: matching version, author ORCID, keywords, no invented DOI.")


if __name__=="__main__":
    main()
