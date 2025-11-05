# OWASP AI Testing Guide - Claude Code Implementation Checklist

## 🎯 Implementation Summary

This checklist guides you through activating the complete Claude Code subagent system for the OWASP AI Testing Guide repository. The system includes 8 specialized agents, security validation hooks, and style configurations designed to maintain the highest standards of AI security testing documentation.

## ✅ Pre-Implementation Verification

### Repository Status
- [ ] Confirm you're in the OWASP AI Testing Guide repository root
- [ ] Verify Jekyll environment: `bundle --version` and `bundle exec jekyll --version`
- [ ] Check current test count: `find Document/content/tests -name "AITG-*.md" | wc -l`
- [ ] Ensure git is properly configured and up-to-date

### Files Created
- [ ] **8 Agent Specifications** in `.claude/agents/`:
  - [ ] `aitg-content-reviewer.md` (auto-triggered security content validation)
  - [ ] `aitg-test-generator.md` (new test methodology creation)
  - [ ] `security-payload-sanitizer.md` (auto-triggered payload sanitization)
  - [ ] `jekyll-site-manager.md` (auto-triggered site management)
  - [ ] `aitg-taxonomy-maintainer.md` (test categorization)
  - [ ] `owasp-standards-validator.md` (OWASP compliance)
  - [ ] `academic-reference-manager.md` (citation management)
  - [ ] `content-link-validator.md` (auto-triggered link validation)

- [ ] **3 Security Hooks** in `.claude/hooks/`:
  - [ ] `security-content-validator.sh` (PreToolUse - blocks unsafe content)
  - [ ] `jekyll-build-validator.sh` (PostToolUse - validates builds)
  - [ ] `aitg-session-init.sh` (SessionStart - provides context)

- [ ] **2 Output Styles** in `.claude/styles/`:
  - [ ] `aitg-security-content.yaml` (security test methodology style)
  - [ ] `aitg-documentation.yaml` (general documentation style)

- [ ] **Complete Configuration**: `CLAUDE.md` (main configuration file)

## 🚀 Implementation Steps

### Step 1: Initialize Claude Code Agent System
```bash
# In Claude Code, run the /agents command to initialize the agent system
/agents
```
**Expected Result**: Claude Code recognizes the 8 agent specifications and makes them available for use.

### Step 2: Add Required MCP Servers
```bash
# Add security research capabilities
claude mcp add security-research

# Add OWASP standards validation
claude mcp add owasp-api
```
**Expected Result**: MCP servers are available for agents that require external data sources.

### Step 3: Enable and Install Verification Hooks
```bash
# Enable the hook system
claude hooks enable

# Install the security and validation hooks
claude hooks install .claude/hooks/

# Verify hooks are active
claude hooks list
```
**Expected Result**: Three hooks are active and will run at appropriate times.

### Step 4: Configure Output Styles
```bash
# Add the AITG-specific output styles
claude style add .claude/styles/aitg-security-content.yaml
claude style add .claude/styles/aitg-documentation.yaml

# Set default style for security content
claude style set aitg-security-content

# Verify styles are available
claude style list
```
**Expected Result**: Custom styles are available and security content style is default.

### Step 5: Test Auto-Triggered Agents
```bash
# Test by editing a security test file (this should trigger aitg-content-reviewer)
# Example: Edit Document/content/tests/AITG-APP-01_Testing_for_Prompt_Injection.md

# Test by modifying Jekyll configuration (this should trigger jekyll-site-manager)
# Example: Edit _config.yml
```
**Expected Result**: Agents automatically activate when their trigger conditions are met.

## 🔍 Verification Tests

### Test 1: Security Content Validation
1. Try to add a line with a real password to any AITG test file
2. Attempt to commit the change
3. **Expected**: Security hook blocks the commit with a clear warning message

### Test 2: Jekyll Build Validation
1. Introduce a syntax error in any markdown file
2. Save the file
3. **Expected**: Build validator detects the error and provides debugging guidance

### Test 3: Agent Auto-Triggering
1. Edit any file in `Document/content/tests/`
2. **Expected**: `aitg-content-reviewer` automatically activates to review changes

### Test 4: Link Validation
1. Add a broken internal link to any documentation file
2. **Expected**: `content-link-validator` detects and reports the broken link

### Test 5: Style Application
1. Ask Claude Code to create new security content
2. **Expected**: Output follows AITG format with proper sanitization markers

## 🛠️ Troubleshooting Common Issues

### Issue: Agents Not Auto-Triggering
**Solution**:
- Verify `/agents` command was run successfully
- Check that agent files are in correct location (`.claude/agents/`)
- Ensure file names match exactly (case-sensitive)

### Issue: Hooks Not Running
**Solution**:
- Run `claude hooks enable` to activate hook system
- Verify hook scripts are executable: `chmod +x .claude/hooks/*.sh`
- Check hook syntax with: `bash -n .claude/hooks/[hook-name].sh`

### Issue: MCP Servers Unavailable
**Solution**:
- Verify MCP servers are properly installed: `claude mcp list`
- Re-add if needed: `claude mcp add security-research owasp-api`
- Check Claude Code documentation for MCP server requirements

### Issue: Jekyll Build Failures
**Solution**:
- Run manual build validation: `bundle exec jekyll build --verbose`
- Check Ruby/Jekyll version compatibility: `bundle env`
- Validate YAML front matter in modified files

### Issue: Style Not Applied
**Solution**:
- Verify styles are installed: `claude style list`
- Set active style: `claude style set aitg-security-content`
- Check YAML syntax in style files

## 📊 Success Metrics

### Immediate Indicators
- [ ] All 8 agents appear in Claude Code agent list
- [ ] Security hooks prevent unsanitized content from being committed
- [ ] Jekyll builds complete without errors after content changes
- [ ] Auto-triggered agents activate when editing relevant files
- [ ] Output follows AITG formatting standards automatically

### Long-term Quality Improvements
- [ ] Reduced security content violations (all payloads properly sanitized)
- [ ] Improved OWASP standards compliance across all test methodologies
- [ ] Consistent academic citation formatting
- [ ] Zero broken internal links in documentation
- [ ] Faster onboarding of new contributors (guided by agents)

## 🎓 Usage Guidance

### For Security Content Creation
1. Use `aitg-test-generator` agent to create new test methodologies
2. Content will be automatically reviewed by `aitg-content-reviewer`
3. Security payloads will be auto-sanitized by `security-payload-sanitizer`
4. OWASP compliance checked by `owasp-standards-validator`

### For Documentation Maintenance
1. Site structure managed automatically by `jekyll-site-manager`
2. Links validated automatically by `content-link-validator`
3. Citations managed by `academic-reference-manager`
4. Test categorization maintained by `aitg-taxonomy-maintainer`

### For Quality Assurance
1. Security hooks prevent unsafe content from entering the repository
2. Build validation ensures site integrity after changes
3. Link validation prevents broken references
4. Style guides ensure consistent, professional output

## 🚨 Important Security Reminders

- **Never commit real credentials**: Always use placeholders like `<SECRET>`, `<API_KEY>`
- **Educational purpose only**: All security examples must include educational disclaimers
- **Responsible disclosure**: Follow ethical security testing principles
- **Sanitized payloads**: All attack examples must be non-actionable
- **Current standards**: Reference latest OWASP frameworks and guidelines

## 📞 Support and Maintenance

### Regular Maintenance Tasks
- **Weekly**: Run link validation across all documentation
- **Monthly**: Update OWASP standard references and tool recommendations
- **Quarterly**: Review and update academic citations
- **As needed**: Add new test methodologies using the generator agent

### Getting Help
- **Agent Issues**: Check `.claude/agents/[agent-name].md` for specific guidance
- **Security Questions**: Review security content validation rules
- **Build Problems**: Run Jekyll build with `--verbose` flag for detailed errors
- **Style Issues**: Check `.claude/styles/` for formatting requirements

---

**🎯 Mission Accomplished**: You now have a comprehensive, security-first Claude Code configuration that maintains the highest standards of AI security testing documentation while ensuring ethical compliance and professional quality.

**Next Steps**: Begin using the system by creating or editing AITG content and observe how the specialized agents automatically assist with maintaining quality and security standards.