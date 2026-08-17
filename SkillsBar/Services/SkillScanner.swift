import Foundation

struct SkillScanner {
    private let fileManager = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    func scanAll(projectSkillRoots: [ProjectSkillRoot] = []) -> [Skill] {
        var skills: [Skill] = []
        skills.append(contentsOf: scanClaudeCodeUserSkills())
        for root in projectSkillRoots where root.isEnabled {
            skills.append(contentsOf: scanClaudeCodeProjectSkills(in: root))
        }
        skills.append(contentsOf: scanClaudeCodePluginSkills())
        skills.append(contentsOf: scanCodexPluginSkills())
        skills.append(contentsOf: scanCodexBuiltInSkills())
        skills.append(contentsOf: scanCodexUserSkills())
        skills.append(contentsOf: scanPiUserSkills())
        skills.append(contentsOf: scanPiSharedSkills())
        for root in projectSkillRoots where root.isEnabled {
            skills.append(contentsOf: scanPiProjectSkills(in: root))
        }
        return skills
    }

    // MARK: - Claude Code

    /// Scans ~/.claude/skills/ for direct child folders containing SKILL.md
    func scanClaudeCodeUserSkills() -> [Skill] {
        let dir = (home as NSString).appendingPathComponent(".claude/skills")
        return scanDirectChildren(dir: dir, source: .claudeCode(.user))
    }

    /// Scans a user-approved project's .claude/skills/ directory for direct child folders containing SKILL.md.
    func scanClaudeCodeProjectSkills(in root: ProjectSkillRoot) -> [Skill] {
        scanDirectChildren(dir: root.claudeSkillsPath, source: .claudeCode(.project(root)))
    }

    /// Recursively scans ~/.claude/plugins/cache/ for any SKILL.md files
    func scanClaudeCodePluginSkills() -> [Skill] {
        let dir = (home as NSString).appendingPathComponent(".claude/plugins/cache")
        guard fileManager.fileExists(atPath: dir) else { return [] }

        var skillsByIdentifier: [String: Skill] = [:]
        guard let enumerator = fileManager.enumerator(atPath: dir) else { return [] }

        while let relativePath = enumerator.nextObject() as? String {
            guard (relativePath as NSString).lastPathComponent == "SKILL.md" else { continue }
            let fullPath = (dir as NSString).appendingPathComponent(relativePath)
            if let skill = parseSkillMD(at: fullPath, source: .claudeCode(.plugin)) {
                let key = skill.triggerCommand.lowercased()
                if let existing = skillsByIdentifier[key] {
                    let newDate = skill.lastModified ?? .distantPast
                    let existingDate = existing.lastModified ?? .distantPast
                    if newDate >= existingDate {
                        skillsByIdentifier[key] = skill
                    }
                } else {
                    skillsByIdentifier[key] = skill
                }
            }
        }

        return Array(skillsByIdentifier.values)
    }

    // MARK: - Codex

    /// Scans ~/.codex/skills/.system/ for built-in skills
    func scanCodexBuiltInSkills() -> [Skill] {
        let dir = (home as NSString).appendingPathComponent(".codex/skills/.system")
        return scanDirectChildren(dir: dir, source: .codexCLI(.builtin), checkAgentYaml: true)
    }

    /// Recursively scans ~/.codex/plugins/cache/ for files matching */skills/*/SKILL.md
    func scanCodexPluginSkills() -> [Skill] {
        let dir = (home as NSString).appendingPathComponent(".codex/plugins/cache")
        guard fileManager.fileExists(atPath: dir) else { return [] }
        guard let enumerator = fileManager.enumerator(atPath: dir) else { return [] }

        var skillsByIdentifier: [String: Skill] = [:]

        while let relativePath = enumerator.nextObject() as? String {
            guard (relativePath as NSString).lastPathComponent == "SKILL.md" else { continue }

            let parentDir = (relativePath as NSString).deletingLastPathComponent
            let skillsDir = (parentDir as NSString).deletingLastPathComponent
            guard (skillsDir as NSString).lastPathComponent == "skills" else { continue }

            let fullPath = (dir as NSString).appendingPathComponent(relativePath)
            let fullParentDir = (dir as NSString).appendingPathComponent(parentDir)

            if let skill = parseSkillMD(at: fullPath, source: .codexCLI(.plugin), checkAgentYaml: true, parentDir: fullParentDir) {
                let key = skill.triggerCommand.lowercased()
                if let existing = skillsByIdentifier[key] {
                    let newDate = skill.lastModified ?? .distantPast
                    let existingDate = existing.lastModified ?? .distantPast
                    if newDate >= existingDate {
                        skillsByIdentifier[key] = skill
                    }
                } else {
                    skillsByIdentifier[key] = skill
                }
            }
        }

        return Array(skillsByIdentifier.values)
    }

    /// Scans ~/.codex/skills/ for user-installed skills (excluding .system)
    func scanCodexUserSkills() -> [Skill] {
        let dir = (home as NSString).appendingPathComponent(".codex/skills")
        guard fileManager.fileExists(atPath: dir) else { return [] }

        var skills: [Skill] = []
        guard let children = try? fileManager.contentsOfDirectory(atPath: dir) else { return [] }

        for child in children where child != ".system" && !child.hasPrefix(".") {
            let childPath = (dir as NSString).appendingPathComponent(child)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: childPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let skillPath = (childPath as NSString).appendingPathComponent("SKILL.md")
            if let skill = parseSkillMD(at: skillPath, source: .codexCLI(.user), checkAgentYaml: true, parentDir: childPath) {
                skills.append(skill)
            }
        }

        return skills
    }

    // MARK: - Pi

    /// Scans ~/.pi/agent/skills/ for nested SKILL.md folders and root-level .md skills.
    func scanPiUserSkills() -> [Skill] {
        let dir = (home as NSString).appendingPathComponent(".pi/agent/skills")
        return scanPiSkillsRoot(dir: dir, source: .pi(.user), includeRootMarkdown: true)
    }

    /// Scans ~/.agents/skills/. Pi ignores root-level .md files in this location.
    func scanPiSharedSkills() -> [Skill] {
        let dir = (home as NSString).appendingPathComponent(".agents/skills")
        return scanPiSkillsRoot(dir: dir, source: .pi(.shared), includeRootMarkdown: false)
    }

    /// Scans a project's .pi/skills/ (root .md allowed) and .agents/skills/ (root .md ignored).
    func scanPiProjectSkills(in root: ProjectSkillRoot) -> [Skill] {
        let source = SkillSource.pi(.project(root))
        return scanPiSkillsRoot(dir: root.piSkillsPath, source: source, includeRootMarkdown: true)
            + scanPiSkillsRoot(dir: root.sharedSkillsPath, source: source, includeRootMarkdown: false)
    }

    /// Applies pi's discovery rules to one skills root: recurse into subdirectories until a
    /// directory holds SKILL.md, and treat that directory as a skill without descending further.
    private func scanPiSkillsRoot(dir: String, source: SkillSource, includeRootMarkdown: Bool) -> [Skill] {
        guard fileManager.fileExists(atPath: dir) else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(atPath: dir) else { return [] }

        var skills: [Skill] = []
        for child in children.sorted() where !child.hasPrefix(".") {
            let childPath = (dir as NSString).appendingPathComponent(child)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: childPath, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                skills.append(contentsOf: collectPiSkillDirs(dir: childPath, source: source))
            } else if includeRootMarkdown, (child as NSString).pathExtension.lowercased() == "md" {
                if let skill = parseSkillMD(at: childPath, source: source, singleFileName: (child as NSString).deletingPathExtension) {
                    skills.append(skill)
                }
            }
        }
        return skills
    }

    /// Walks one subtree. A directory containing SKILL.md is a skill root and is not descended into.
    private func collectPiSkillDirs(dir: String, source: SkillSource) -> [Skill] {
        let skillPath = (dir as NSString).appendingPathComponent("SKILL.md")
        if fileManager.fileExists(atPath: skillPath) {
            guard let skill = parseSkillMD(at: skillPath, source: source, parentDir: dir) else { return [] }
            return [skill]
        }

        guard let children = try? fileManager.contentsOfDirectory(atPath: dir) else { return [] }
        var skills: [Skill] = []
        for child in children.sorted() where !child.hasPrefix(".") {
            let childPath = (dir as NSString).appendingPathComponent(child)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: childPath, isDirectory: &isDir), isDir.boolValue else { continue }
            skills.append(contentsOf: collectPiSkillDirs(dir: childPath, source: source))
        }
        return skills
    }

    // MARK: - Helpers

    private func scanDirectChildren(dir: String, source: SkillSource, checkAgentYaml: Bool = false) -> [Skill] {
        guard fileManager.fileExists(atPath: dir) else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(atPath: dir) else { return [] }

        var skills: [Skill] = []
        for child in children where !child.hasPrefix(".") {
            let childPath = (dir as NSString).appendingPathComponent(child)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: childPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let skillPath = (childPath as NSString).appendingPathComponent("SKILL.md")
            if let skill = parseSkillMD(at: skillPath, source: source, checkAgentYaml: checkAgentYaml, parentDir: childPath) {
                skills.append(skill)
            }
        }
        return skills
    }

    /// `singleFileName` marks a standalone .md skill (pi allows these at a skills-root). For those the
    /// path is the skill itself, so sibling files must not be reported as this skill's folder contents.
    private func parseSkillMD(at path: String, source: SkillSource, checkAgentYaml: Bool = false, parentDir: String? = nil, singleFileName: String? = nil) -> Skill? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let fallbackName = singleFileName ?? URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
        guard let parsed = FrontmatterParser.parse(content: content) else {
            // If no valid frontmatter, still create a skill with the folder or file name
            return Skill(name: fallbackName, description: "", source: source, path: path)
        }

        var name = parsed.name
        var description = parsed.description

        // For Codex skills, check agents/openai.yaml for better display info
        if checkAgentYaml, let dir = parentDir {
            let agentPath = (dir as NSString).appendingPathComponent("agents/openai.yaml")
            if let agentContent = try? String(contentsOfFile: agentPath, encoding: .utf8) {
                let agent = FrontmatterParser.parseOpenAIAgent(content: agentContent)
                if let displayName = agent.displayName, !displayName.isEmpty {
                    name = displayName
                }
                if let shortDesc = agent.shortDescription, !shortDesc.isEmpty, description.isEmpty {
                    description = shortDesc
                }
            }
        }

        // Fallback name to folder or file name
        if name.isEmpty {
            name = fallbackName
        }

        // File metadata
        let skillDir = (path as NSString).deletingLastPathComponent
        let lastModified = (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        let allItems: [String]
        if singleFileName != nil {
            // A standalone .md skill owns no folder, so list only itself.
            allItems = [(path as NSString).lastPathComponent]
        } else {
            allItems = (try? fileManager.contentsOfDirectory(atPath: skillDir))?
                .filter { !$0.hasPrefix(".") }
                .sorted() ?? []
        }
        var directories: Set<String> = []
        var dirContents: [String: [String]] = [:]
        for item in allItems where singleFileName == nil {
            var isDir: ObjCBool = false
            let itemPath = (skillDir as NSString).appendingPathComponent(item)
            if fileManager.fileExists(atPath: itemPath, isDirectory: &isDir), isDir.boolValue {
                directories.insert(item)
                dirContents[item] = (try? fileManager.contentsOfDirectory(atPath: itemPath))?
                    .filter { !$0.hasPrefix(".") }
                    .sorted() ?? []
            }
        }

        return Skill(name: name, description: description, source: source, path: path, version: parsed.version, body: parsed.body, lastModified: lastModified, folderContents: allItems, folderDirectories: directories, directoryContents: dirContents)
    }
}
