// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

extension ShellWidgetHost {
    func permissionsChanged() {
        networkApprovals = networkApprovals.filter { isPending($0.key) }
        for state in widgets.values {
            state.mailbox?.yield(.permissions)
            state.loadingPackage?.permissionsChanged()
        }
        hiddenBarMenu?.permissionsChanged()
    }

    func recordNetworkApprovals(_ approvals: [ShellNetworkApproval]) {
        for approval in approvals where isPending(approval.key) {
            networkApprovals[approval.key] = approval
        }
    }

    private func isPending(_ key: ShellNetworkApproval.Key) -> Bool {
        permissions.undecided(key.hosts, for: key.principal).hosts == key.hosts
    }
}
