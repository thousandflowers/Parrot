import Foundation

struct RuleResolver {
    static func resolve(
        appBundleID: String?,
        customPrompts: [CustomPrompt],
        appRules: [AppRule]
    ) -> (serviceType: ServiceType?, prompt: CustomPrompt?) {
        guard let bundleID = appBundleID,
              let rule = appRules.first(where: { $0.bundleID == bundleID && $0.isEnabled })
        else {
            return (nil, nil)
        }
        let prompt: CustomPrompt?
        if let promptID = rule.promptID {
            prompt = customPrompts.first(where: { $0.id == promptID })
        } else {
            prompt = nil
        }
        return (rule.serviceType, prompt)
    }
}
