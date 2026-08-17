import Foundation

struct ProjectSkillRoot: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var isEnabled: Bool
    var isPinned: Bool
    var trustedContentSignature: String?
    let createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case isEnabled
        case isPinned
        case trustedContentSignature
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        name: String? = nil,
        path: String,
        isEnabled: Bool = true,
        isPinned: Bool = false,
        trustedContentSignature: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let standardizedPath = (path as NSString).standardizingPath
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.path = standardizedPath
        if let trimmedName, !trimmedName.isEmpty {
            self.name = trimmedName
        } else {
            self.name = URL(fileURLWithPath: standardizedPath).lastPathComponent
        }
        self.isEnabled = isEnabled
        self.isPinned = isPinned
        self.trustedContentSignature = trustedContentSignature
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Project"
        path = (try container.decode(String.self, forKey: .path) as NSString).standardizingPath
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        trustedContentSignature = try container.decodeIfPresent(String.self, forKey: .trustedContentSignature)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    var claudeSkillsPath: String {
        (path as NSString).appendingPathComponent(".claude/skills")
    }

    var claudeAgentsPath: String {
        (path as NSString).appendingPathComponent(".claude/agents")
    }

    /// Pi's project-local skills directory.
    var piSkillsPath: String {
        (path as NSString).appendingPathComponent(".pi/skills")
    }

    /// Harness-neutral project skills directory from the Agent Skills standard. Pi reads it; Claude Code does not.
    var sharedSkillsPath: String {
        (path as NSString).appendingPathComponent(".agents/skills")
    }

    /// Every project directory that can hold skills, in the order sections are shown.
    var skillDirectoryPaths: [String] {
        [claudeSkillsPath, piSkillsPath, sharedSkillsPath]
    }

    var instructionCandidatePaths: [String] {
        ProjectInstructionKind.allCases.map { kind in
            (path as NSString).appendingPathComponent(kind.relativePath)
        }
    }
}

enum ProjectSkillRootStatus: Equatable {
    case disabled
    case available
    case missingSkillsFolder
    case missingProjectFolder

    var title: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .available:
            return "Ready"
        case .missingSkillsFolder:
            // Neutral wording: a project can carry .claude/skills, .pi/skills, or .agents/skills.
            return "No skills folder"
        case .missingProjectFolder:
            return "Missing"
        }
    }

    var isUnavailable: Bool {
        switch self {
        case .missingSkillsFolder, .missingProjectFolder:
            return true
        case .disabled, .available:
            return false
        }
    }
}

enum ProjectInstructionKind: String, CaseIterable, Hashable {
    case claudeRoot
    case codexRoot
    case codexScoped
    case piOverride

    var relativePath: String {
        switch self {
        case .claudeRoot:
            return "CLAUDE.md"
        case .codexRoot:
            return "AGENTS.md"
        case .codexScoped:
            return ".codex/AGENTS.md"
        case .piOverride:
            return "AGENTS.override.md"
        }
    }

    var displayName: String {
        relativePath
    }

    /// Which harnesses read this file. Pi reads CLAUDE.md and AGENTS.md too, and
    /// prefers AGENTS.override.md over both when it is present in a directory.
    var sourceLabel: String {
        switch self {
        case .claudeRoot:
            return "Claude Code, Pi"
        case .codexRoot:
            return "Codex, Pi"
        case .codexScoped:
            return "Codex"
        case .piOverride:
            return "Pi"
        }
    }
}

struct ProjectInstructionFile: Identifiable, Hashable {
    let kind: ProjectInstructionKind
    let path: String
    let lastModified: Date?

    var id: String { path }
    var displayName: String { kind.displayName }
    var sourceLabel: String { kind.sourceLabel }
}

struct ProjectSkillConflict: Identifiable, Hashable {
    let skill: Skill
    let summary: SkillConflictSummary

    var id: String { skill.path }
}

enum ProjectTrustStatus: Equatable {
    case unavailable
    case noTrackedFiles
    case trusted
    case needsReview

    var title: String {
        switch self {
        case .unavailable:
            return "Unavailable"
        case .noTrackedFiles:
            return "No extra files"
        case .trusted:
            return "Trusted"
        case .needsReview:
            return "Review changes"
        }
    }

    var needsAction: Bool {
        self == .needsReview
    }
}

enum SkillSourceCategory: String, CaseIterable, Hashable {
    case user
    case plugin
    case project
    case builtin
    /// Harness-neutral ~/.agents/skills location. Searchable as `source:shared`.
    case shared
}

struct SkillConflictSummary: Hashable {
    let triggerMatchCount: Int
    let nameMatchCount: Int
    let matchingSkillDescriptions: [String]
    let conflictingSkillPaths: [String]

    var totalCount: Int {
        matchingSkillDescriptions.count
    }

    var label: String {
        totalCount == 1 ? "Conflict" : "\(totalCount) conflicts"
    }

    var helpText: String {
        var lines: [String] = []

        if triggerMatchCount > 0 {
            lines.append("\(triggerMatchCount) matching trigger")
        }
        if nameMatchCount > 0 {
            lines.append("\(nameMatchCount) matching name")
        }

        lines.append(contentsOf: matchingSkillDescriptions.prefix(8))

        if matchingSkillDescriptions.count > 8 {
            lines.append("and \(matchingSkillDescriptions.count - 8) more")
        }

        return lines.joined(separator: "\n")
    }
}

enum SkillSource: Hashable {
    case claudeCode(ClaudeCodeSection)
    case codexCLI(CodexSection)
    case pi(PiSection)

    enum ClaudeCodeSection: Hashable {
        case user
        case plugin
        case project(ProjectSkillRoot)

        var title: String {
            switch self {
            case .user:
                return "User Skills"
            case .plugin:
                return "Plugin Skills"
            case .project:
                return "Project Skill"
            }
        }
    }

    enum CodexSection: String, Hashable {
        case builtin = "Built-in Skills"
        case plugin = "Plugin Skills"
        case user = "User Skills"
    }

    /// Pi has no sub-agents and no plugin-skill cache. It reads two global skill
    /// directories and two project-local ones. See pi docs/skills.md.
    enum PiSection: Hashable {
        /// ~/.pi/agent/skills
        case user
        /// ~/.agents/skills
        case shared
        /// <project>/.pi/skills and <project>/.agents/skills
        case project(ProjectSkillRoot)

        var title: String {
            switch self {
            case .user:
                return "User Skills"
            case .shared:
                return "Shared Skills"
            case .project:
                return "Project Skill"
            }
        }
    }

    var groupTitle: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codexCLI: return "Codex"
        case .pi: return "Pi"
        }
    }

    var sectionTitle: String {
        switch self {
        case .claudeCode(let section): return section.title
        case .codexCLI(let section): return section.rawValue
        case .pi(let section): return section.title
        }
    }

    var projectName: String? {
        switch self {
        case .claudeCode(.project(let root)), .pi(.project(let root)):
            return root.name
        case .claudeCode, .codexCLI, .pi:
            return nil
        }
    }

    var projectRootPath: String? {
        switch self {
        case .claudeCode(.project(let root)), .pi(.project(let root)):
            return root.path
        case .claudeCode, .codexCLI, .pi:
            return nil
        }
    }

    var isProjectSkill: Bool {
        projectRootPath != nil
    }

    /// The harness namespace this skill is loaded into. Two skills can only shadow each
    /// other when one harness loads both, so conflict checks group on this. The same skill
    /// symlinked into Claude Code and Pi is available twice, not in conflict.
    var harnessID: String {
        switch self {
        case .claudeCode: return "claude-code"
        case .codexCLI: return "codex"
        case .pi: return "pi"
        }
    }

    var searchCategory: SkillSourceCategory {
        switch self {
        case .claudeCode(.user), .codexCLI(.user), .pi(.user):
            return .user
        case .claudeCode(.plugin), .codexCLI(.plugin):
            return .plugin
        case .claudeCode(.project), .pi(.project):
            return .project
        case .codexCLI(.builtin):
            return .builtin
        case .pi(.shared):
            return .shared
        }
    }

    var shortScopeLabel: String {
        switch self {
        case .claudeCode(.user):
            return "Claude user"
        case .claudeCode(.plugin):
            return "Claude plugin"
        case .claudeCode(.project(let root)):
            return "\(root.name) project"
        case .codexCLI(.builtin):
            return "Codex built-in"
        case .codexCLI(.plugin):
            return "Codex plugin"
        case .codexCLI(.user):
            return "Codex user"
        case .pi(.user):
            return "Pi user"
        case .pi(.shared):
            return "Shared"
        case .pi(.project(let root)):
            return "\(root.name) project"
        }
    }

    /// An image-set name when `isCustomIcon` is true, otherwise an SF Symbol name.
    var iconName: String {
        switch self {
        case .claudeCode: return "ClaudeLogo"
        case .codexCLI: return "CodexLogo"
        case .pi: return "pi"
        }
    }

    var isCustomIcon: Bool {
        switch self {
        case .claudeCode, .codexCLI: return true
        case .pi: return false
        }
    }

    var badgeColor: String {
        switch self {
        case .claudeCode(.user): return "orange"
        case .claudeCode(.plugin): return "orange"
        case .claudeCode(.project(_)): return "blue"
        case .codexCLI(.builtin): return "purple"
        case .codexCLI(.plugin): return "purple"
        case .codexCLI(.user): return "purple"
        case .pi(.user): return "pink"
        case .pi(.shared): return "pink"
        case .pi(.project(_)): return "blue"
        }
    }
}
