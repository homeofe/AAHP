---
name: Bug Report
about: Report a bug to help us improve
labels: bug
---

**Describe the bug**
A clear description of what the bug is.

**To Reproduce**
Steps to reproduce:
1. ...
2. ...

**Expected behavior**
What you expected to happen.

**Additional context**
Any other context about the problem.

**Acceptance criteria**
<!--
Task boxes, never plain bullets: "- [ ]" while unresolved, "- [x]" only on evidence
(commit, PR, test run, live verification). Before this issue is closed, every box is
checked, waived "(waived: rationale)", or moved "(follow-up: #123)".
-->
- [ ] Root cause identified and described
- [ ] Fix implemented with a regression test that fails without it
- [ ] `npm run check`, `npm run doctor`, and `npm test` pass
