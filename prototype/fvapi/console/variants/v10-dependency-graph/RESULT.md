# v10-dependency-graph

Deliverable = static dependency atlas; validator input for integration.

| Check | Result |
|---|---|
| Design plan | pass: PLAN.md |
| API-driven content | pass: relative /v0 requests; no response fixtures embedded |
| Graph/list interaction | pass: Neo list toggle; 3 fixture entries reachable |
| Required state captures | pass: 11 PNGs; webcap rc 0; 10/10 captured DOM state assertions pass |
| Every capture inspected | pass: every PNG opened; no blank states; sticky graph shifts down in full-page check captures |
| Mobile overflow | pass: 390 px capture inspected; list defaults on narrow screens; replay column corrected + recaptured |
| Browser errors | partial: window error/unhandledrejection capture empty across list, accept/reject, 409, miss/hit, copy, keyboard-node interactions; startup console not captured (Neo CDP target_scope_unsupported) |
| Action checks | pass: Neo accept→edit one weight→reject; no_checker 409; lookup miss/hit + 5 highlighted edges; copy command; Enter selects file node |
| Static checks | pass: node --check rc 0; git diff --check rc 0 |
| Contrast | pass: ink/paper 12.38:1; blue/white 6.68:1; green/paper 6.88:1; rust/paper 6.58:1 |
| Git posture | scoped to variant directory; closing commit on wt/v10-dependency-graph; never pushed |

Run: `python3 prototype/fvapi/mock.py 8460`; URL `http://127.0.0.1:8460/console/v10-dependency-graph/`.

State hashes: catalog, entry, recorded, lookup-hit, lookup-miss, check-accept, check-reject, check-409, demand, answers. Mobile = entry at 390 px.

Known limits: mock catalog has 3 entries, not the eventual 5. Mock bundles return 404; download link targets the real API route. Mock demand/answers are fixed fixture logs; a lookup miss response confirms demand logging but does not mutate those fixture logs. Full startup console capture not checked.
