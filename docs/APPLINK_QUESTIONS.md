# Questions for Applink and the business mentor

*Copied from sections 12.2 and 12.3 of the build plan (`docs/LaMP-Build-Plan.md`), updated 27 Nov 2026. The plan is the source: change it first, then this file.*

**Nothing in the build waits on these answers.** Every question has a default the build uses until it's answered. Test items refer to the sandbox checklist in the plan's section 9.4.

**How to use this file**

1. As soon as both apps are approved, run sandbox items 1–7 (plan 9.4). Write what happened in the answers log below.
2. Send the message below ("The message to Applink") to Khaled Md Raihan, leaving out anything a test already answered, and adding any test that failed, with its status code.
3. Send Q17 and Q18 to the business mentor separately.
4. Write every answer in the log, and change the plan where an answer changes a default.

## The questions (plan 12.2)

Every question has a default that the build uses until it's answered. **Test** rows are settled by our own sandbox checklist (9.4) as soon as the apps are approved, so we ask only if a test fails or leaves it unclear. **Ask** rows go to Applink in one message after the first sandbox run (12.3). **Answered** rows were settled by the Applink form on 26 Nov.

| Q | Question | How it gets settled | Default until then |
|---|---|---|---|
| Q1 | (Spec Q1) With MT charging off, does LaMP pay anything per SMS? Does a family pay anything to text 21213? | **Ask** | Free to families; BDT 0 to LaMP; R5 if not |
| Q2 | (Spec Q2) Must the owner have a Banglalink number? Can families on other networks text 21213? | **Ask** | Owners on Banglalink; other networks use the web card |
| Q3 | (Spec Q3) Is it fine to run two apps (a free core and a paid Plus) under one SP account? Can Plus start with `/subscription/send` using the core app's id? | **Test** item 19, then **ask** | Two apps; Plus starts with an OTP on the Plus app |
| Q4 | (Spec Q4) Is BDT 50 a month right for LaMP Plus? | **Answered** (form): monthly 10, 15, 30, 50, 60 or 70; daily 1, 2, 3 or 5 | BDT 50 monthly (team decision) |
| Q5 | (Spec Q5) What does approval for live use need, and how long does it take before 16 Dec? | **Ask** | Request it as soon as Phase 2 starts |
| Q6 | Can a subscription app run with charging off (a free subscription) and still use OTP, SMS and CaaS? | **Ask**; approval shows it | Yes (R3 if not) |
| Q7 | What happens when we call `/subscription/send` for a family? The form has no "subscriber confirmation" switch. Is an app-started subscription allowed at all? | **Test** item 7 | `/subscription/send`, a 48-hour wait; R4 |
| Q8 | Which texts to 21213 does Applink handle itself (for example `STOP LAMP`, `START LAMP`), and which reach us? Is `21213` an allowed `sourceAddress`? | Short code and keyword **answered** (21213, `lamp`); the rest by **test** items 6 and 15, then **ask** | Our commands start with `LAMP`; `sourceAddress` left out |
| Q9 | From which IP ranges do callbacks come? Can callback URLs hold a secret path segment? | **Test** item 21 (log the source IPs), then **ask** | Secret path yes; IP list off until known |
| Q10 | Is Bangla (Unicode) SMS supported? How many characters a part, and is each part charged? | **Test** item 8 (parts); **ask** (charging) | Yes, 70 a part, each part counted |
| Q11 | Is a subscriber's masked id the same in both apps? | **Test** items 3 and 19 | Different; Plus has its own OTP |
| Q12 | Is BDT 10 an allowed CaaS amount? | **Answered** (form): 2, 5, 7 or 10, within BDT 1–50 | BDT 10 |
| Q13 | In limited production, do OTP, CaaS and subscription work for whitelisted numbers? How many numbers can we whitelist? Can we keep a third "staging" app in limited production after going live? | **Test** items 2, 7 and 17; **ask** the rest | 10 numbers; a staging app in Phase 2 |
| Q14 | Does Applink forward a text from a non-subscriber (`LAMP <code>`) to our app, and may we reply? | **Test** item 6 | Both orders built (3.4 step 5); R19 |
| Q15 | When a family texts to join, or the pharmacy adds their number at the counter with their agreement, does either need hSenid's written consent under the "no direct approaching of customers" clause? | **Ask** | Joining by text is the family's own request; ask for written OK for the counter route |
| Q16 | The form says "Developer will receive 40% of the revenue". Before or after VAT? Does it cover CaaS, and what is CaaS's 20% service charge? | **Ask** (moved here from the business mentor) | 40% of the base price for both (section 14) |
| Q17 | Can you help us reach pharmacy networks for the first pilot? | **Ask the business mentor** | Drug reps and the district association (spec 7.3) |
| Q18 | Can LaMP use Banglalink's promotion channels (the Applink store, free SMS promotions, Adcore)? | **Ask the business mentor** | Apply after going live; no bulk SMS ever |
| Q19 | The allowed-host field rejects CIDR, so we listed all 508 addresses of Render's two Singapore ranges. Is that acceptable, or would you prefer one fixed IP? | CIDR **answered** (rejected); **ask** the rest | 508 single IPs; fallbacks in R14 |
| Q20 | (Market brief) Will USSD keep working on 4G-only button phones after the 2G switch-off? | **Dropped** with USSD; SMS works on 4G button phones | — |
| Q21 | Advertisements and number masking are locked on in our form. Can you turn both off for both apps? | **Ask**; item 8 shows what ads do to our SMS | Masking on (families join by text); ads measured |
| Q22 | Is USSD available to hackathon apps? Every keyword under `*213#` shows as unavailable. | **Ask** (low priority) | No USSD (R2) |
| Q23 | Can the SMS limits (5 a second, 20,000 a day) be raised when we go live? | **Ask** (low priority) | Throttle at 4 a second; alert at 15,000 a day |

## The message to Applink (plan 12.3)

- **To:** Khaled Md Raihan (Applink POC) in the team lead communication group, or support@applink.com.bd.
- **From:** Arifin; Ishmam posts it if only the team lead can write in the group.
- **When:** after sandbox items 1–7. Leave out anything a test already answered, and add any item that failed, with its status code.
- **The business mentor** gets Q17 and Q18 separately.
- **Map:** the message's items are Q1, Q2, Q3 and Q6, Q5, Q8, Q9, Q10, Q13, Q15, Q16, Q19, Q21, Q22, Q23.

> Hello Khaled bhai, team IUT_GrandHackAuto (LaMP) here. Our apps are LaMP (APP_019205) and LaMPPlus (APP_019207) under the SP account ISHMAM259. A few things we couldn't settle from the docs or our own tests:
>
> 1. With MT charging off, do we pay anything per SMS? Does a family pay anything to text 21213?
> 2. Must owners have a Banglalink number? Can families on other networks text 21213?
> 3. Is it fine to run two apps, a free core and a paid Plus, under one SP account? And can a free subscription app (charging off) go live?
> 4. What does approval for live use need, and how long does it take? We'd like to be live by 16 Dec.
> 5. Which texts to 21213 does Applink handle itself (for example STOP LAMP or START LAMP)? Can we send from 21213 as the sourceAddress?
> 6. From which IP ranges do your callbacks come?
> 7. Is each part of a Bangla SMS charged separately?
> 8. How many numbers can we whitelist, and can we keep a third staging app in limited production after going live?
> 9. When a family texts LAMP and their card code to join, or a pharmacy adds a family's number at the counter with their agreement, does either need hSenid's written consent under the "no direct approaching of customers" clause?
> 10. The form says the developer gets 40% of the revenue. Is that before or after VAT, does it cover CaaS, and what is the 20% CaaS service charge?
> 11. The Allowed Host field doesn't take ranges, so we listed all 508 addresses of Render's two Singapore ranges (74.220.52.0/24 and 74.220.60.0/24). Is that acceptable, or would you prefer one fixed IP?
> 12. Advertisements and number masking are locked on in our form. Our SMS are about health and money, so could you turn both off for our two apps?
> 13. Is USSD available to hackathon apps? Every keyword under *213# shows as unavailable, so we've built without it.
> 14. Can the SMS limits (5 a second, 20,000 a day) be raised when we go live?
>
> Thank you!

## Answers log

| Q | When | Answer | From (test item, Khaled, support, mentor) | Plan change needed |
|---|---|---|---|---|
| Q4 | 26 Nov | Monthly BDT 10, 15, 30, 50, 60 or 70; daily 1, 2, 3 or 5 | Applink form | None: BDT 50 monthly kept |
| Q8 | 26 Nov | Short code 21213; keyword `lamp` (lower case); the rest still open | Applink form | Done (3.1, 3.5) |
| Q12 | 26 Nov | CaaS amounts 2, 5, 7 or 10, within BDT 1–50; 20% service charge | Applink form | None: BDT 10 kept |
| Q19 | 26 Nov | CIDR rejected; all 508 single addresses entered | Applink form | Done (3.1, R14) |
| Q22 | 26 Nov | Every keyword `000`–`999` on `*213#` refused | Applink form | Done: USSD dropped |
