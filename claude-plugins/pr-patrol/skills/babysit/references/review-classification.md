# Review Comment Classification

Shared taxonomy for classifying PR review comments. Used by both babysit and post-merge-sweeper workers.

## Triviality

**Trivial** — safe to auto-fix without human judgment:
- Naming / rename suggestion
- Typo fix
- Import ordering / unused import
- Missing type annotation
- Formatting / whitespace
- Adding or removing a comment/docstring
- Simple refactor with explicit suggested code from reviewer

**Non-trivial** — requires human judgment (auto-fix only in `--yolo` mode):
- Logic changes
- Architecture / design decisions
- Performance concerns
- Security issues
- Anything requiring judgment
- Anything where the right fix isn't obvious from the comment

## Severity

**Meaningful** (always surface):
- Bug, logic error, incorrect behavior
- Security concern, data loss risk
- Missing error handling
- Missing test coverage
- Wrong type

**Improvement** (surface):
- Performance issue
- Better API usage
- Missing validation
- Readability concern with substance

**Cosmetic** (drop — don't surface or fix):
- Style preferences on merged code
- Formatting on merged code
- Subjective naming preferences

## Skip Rules

Always skip comments that are:
- Authored by the PR author (self-comments)
- From known bots: `olive-agent`, `dependabot`, `renovate`, `github-actions`
- Praise or acknowledgment: "nice!", "LGTM", "good call", "+1"
- Hedged: starts with "nit:", "optional:", "take it or leave it", "minor:"

## Confidence Scoring (post-merge sweeper only)

When analyzing merged PRs, assess whether the comment was addressed in the final code:

- **High confidence (keep):** Comment suggests specific change not present in final code
- **High confidence (keep):** Comment points out a bug, code at that location is unchanged
- **Medium confidence (keep):** Comment raises architectural concern, no evidence it was addressed
- **Low confidence (drop):** Question that may have been answered in conversation
- **Low confidence (drop):** Nitpick or subjective preference
