# Mirrorly — Store Privacy Answers

Definitive reference for the App Store **App Privacy questionnaire** and Google Play **Data Safety form**. Every category is covered. Reviewers should have zero open questions after reading this — match the answers below to what's in `lib/screens/legal/legal_screen.dart`.

These answers reflect what Mirrorly actually does:

- On-device camera capture + ML Kit / MediaPipe face detection (entirely local).
- 16 facial-geometry numbers (canthal tilt, jaw angle, FWHR, symmetry, thirds, etc.) computed on-device.
- Selfie photo bytes + geometry numbers sent to OpenAI (GPT-4o Vision) and Replicate (Nano Banana, face-swap) for one API call each — analysis text + rendered "maximized" image are returned and the providers retain nothing per their default API terms.
- Scan history + generated images + active protocol persisted in the app sandbox on-device.
- RevenueCat handles subscription receipts.
- No accounts. No name. No email. No phone. No location. No analytics SDK. No crash-reporting SDK. No advertising IDs.

---

## PART 1 — Apple App Store · App Privacy questionnaire

For every category Apple lists, this section gives the answer plus the rationale a reviewer would expect.

### 1. Contact Info
| Sub-type | Collected? |
|---|---|
| Name | **NO** |
| Email Address | **NO** |
| Phone Number | **NO** |
| Physical Address | **NO** |
| Other User Contact Info | **NO** |

### 2. Health & Fitness
| Sub-type | Collected? |
|---|---|
| Health | **NO** |
| Fitness | **NO** |

(Mirrorly is a cosmetic-self-assessment tool, not a health app.)

### 3. Financial Info
| Sub-type | Collected? |
|---|---|
| Payment Info | **NO** (Apple/Google handle billing — Mirrorly never sees card numbers.) |
| Credit Info | **NO** |
| Other Financial Info | **NO** |

### 4. Location
| Sub-type | Collected? |
|---|---|
| Precise Location | **NO** |
| Coarse Location | **NO** |

### 5. Sensitive Info
| Sub-type | Collected? |
|---|---|
| Sensitive Info | **NO** |

(Apple's "Sensitive Info" is religious belief, sexual orientation, gender identity, race, political opinion, etc. None of those are collected.)

### 6. Contacts
| Sub-type | Collected? |
|---|---|
| Contacts | **NO** |

### 7. User Content
| Sub-type | Collected? | Linked? | Tracking? | Purposes |
|---|---|---|---|---|
| Emails or Text Messages | NO | – | – | – |
| **Photos or Videos** | **YES** | **Linked** (it's the user's face) | **No** | App Functionality |
| Audio Data | NO | – | – | – |
| Gameplay Content | NO | – | – | – |
| Customer Support | NO | – | – | – |
| **Other User Content** *(the geometry numbers — canthal tilt, jaw angle, etc.)* | **YES** | **Linked** | **No** | App Functionality |

### 8. Browsing History
| Sub-type | Collected? |
|---|---|
| Browsing History | **NO** |

### 9. Search History
| Sub-type | Collected? |
|---|---|
| Search History | **NO** |

### 10. Identifiers
| Sub-type | Collected? | Linked? | Tracking? | Purposes |
|---|---|---|---|---|
| User ID | **NO** (no accounts) | – | – | – |
| Device ID | **NO** (no advertising ID, no IDFA) | – | – | – |

### 11. Purchases
| Sub-type | Collected? | Linked? | Tracking? | Purposes |
|---|---|---|---|---|
| **Purchase History** | **YES** (via RevenueCat) | **Linked** (to App Store / Play account) | **No** | App Functionality |

### 12. Usage Data
| Sub-type | Collected? |
|---|---|
| Product Interaction | **NO** (no analytics SDK shipped) |
| Advertising Data | **NO** |
| Other Usage Data | **NO** |

### 13. Diagnostics
| Sub-type | Collected? |
|---|---|
| Crash Data | **NO** (no Crashlytics, no Sentry) |
| Performance Data | **NO** |
| Other Diagnostic Data | **NO** |

### 14. Other Data
| Sub-type | Collected? |
|---|---|
| Other Data Types | **NO** |

### Apple — Tracking
**Does the app track users across apps and websites owned by other companies?** → **NO**

(No ATT prompt is required because Mirrorly does not engage in tracking as Apple defines it.)

### Apple — Data Linked vs. Not Linked
- **Photos** → *Linked to user* (it's their face)
- **Other User Content (geometry)** → *Linked to user*
- **Purchase History** → *Linked to user* (to their App Store ID, for subscription validation)

All other categories: not collected at all, so the linked / not-linked / tracking columns don't apply.

---

## PART 2 — Google Play · Data Safety form

For every Play category, this section gives the answer + the four required attributes (Collected, Shared, Optional, Purposes).

### Personal info
| Sub-type | Collected? | Shared? | Optional? | Purposes |
|---|---|---|---|---|
| Name | NO | – | – | – |
| Email address | NO | – | – | – |
| User IDs | NO | – | – | – |
| Address | NO | – | – | – |
| Phone number | NO | – | – | – |
| Race and ethnicity | NO | – | – | – |
| Political or religious beliefs | NO | – | – | – |
| Sexual orientation | NO | – | – | – |
| **Other info** *(the 16 facial-geometry scalar numbers + score)* | **YES** | **No** | **Required** | **App functionality** |

### Financial info
| Sub-type | Collected? | Shared? | Optional? | Purposes |
|---|---|---|---|---|
| User payment info | NO (Play handles billing) | – | – | – |
| Purchase history | YES (via RevenueCat) | No | Required | App functionality, Account management |
| Credit score | NO | – | – | – |
| Other financial info | NO | – | – | – |

### Health and fitness
| Sub-type | Collected? |
|---|---|
| Health info | NO |
| Fitness info | NO |

### Messages
All sub-types: NO.

### Photos and videos
| Sub-type | Collected? | Shared? | Optional? | Purposes |
|---|---|---|---|---|
| **Photos** | **YES** | **YES — shared with OpenAI and Replicate for the duration of one API request, then forgotten** | **Required** (the app is a face-scan analyser) | **App functionality, Personalization** |
| Videos | NO | – | – | – |

### Audio files
All sub-types: NO.

### Files and docs
All sub-types: NO.

### Calendar
NO.

### Contacts
NO.

### App activity
| Sub-type | Collected? | Shared? | Optional? | Purposes |
|---|---|---|---|---|
| App interactions | NO (no analytics SDK) | – | – | – |
| In-app search history | NO | – | – | – |
| Installed apps | NO | – | – | – |
| **Other user-generated content** *(your AI verdict text, your "after" rendered image URL, your active protocol)* | **YES** | **No** | **Required** | **App functionality** |
| Other actions | NO | – | – | – |

### Web browsing
NO.

### App info and performance
| Sub-type | Collected? |
|---|---|
| Crash logs | NO (no Crashlytics) |
| Diagnostics | NO |
| Other app performance data | NO |

### Device or other IDs
NO. No advertising identifiers, no device fingerprint.

---

## PART 3 — Special / yes-no questions both stores ask

| Question | Answer |
|---|---|
| Is data encrypted in transit? | **YES** — all backend calls go over HTTPS to our API and to OpenAI / Replicate. |
| Do you provide a way for users to request deletion? | **YES** — uninstalling the app deletes all on-device data; transient server-side request data auto-expires. Email contact at `hello@mirrorly.app` is in the Privacy Policy for written deletion requests. |
| Does the app collect data from children under 13? | **NO** — minimum age 13 is stated in the Terms of Use. |
| Does the app commit to the Google Play Families policy? | **NO** — Mirrorly is for adult / teen-13+ self-assessment, not children. |
| Does the app track users across apps / websites? *(Apple ATT)* | **NO** |
| **Does the app collect biometric data?** | **NO** — see open-text answer below. |
| Does the app use ARKit / Face ID for authentication? | **NO** — face data is used only for cosmetic measurement, not identity verification. |

---

## PART 4 — Open-text explanations · paste verbatim if asked

### "Why do you collect Photos / Videos?"

> Mirrorly captures a selfie photo so the app can compute facial-geometry measurements (eye position, jaw angle, symmetry, proportions) for cosmetic self-assessment, and so the on-screen "maximized" preview can illustrate possible grooming changes applied to the user's own photo. The photo is sent to OpenAI (GPT-4o Vision) and Replicate (Nano Banana, cdingram/face-swap) for the duration of one API request to produce the analysis prose and the rendered preview image, then those providers discard the photo per their default API terms. Mirrorly does not retain a server-side copy of the photo, does not perform facial recognition, does not match the photo against any database, does not train AI on it, does not share it with advertisers or data brokers. The on-device copy stays in the app's sandboxed documents directory and is deleted when the user uninstalls the app.

### "Why do you collect Other Personal Info / Other User Content (geometry numbers)?"

> Mirrorly computes 16 scalar facial-geometry measurements on-device (canthal tilt in degrees, jaw angle in degrees, face width-to-height ratio, symmetry score, facial-thirds proportions, etc.) so the app can render the user's score, surface trait badges, and pick an archetype match. These measurements are plain numbers describing facial shape; they are not a biometric template, are not used for identity recognition, and cannot be reversed back into a face. They are stored only on the user's device.

### "Does the app collect biometric data? Why / why not?"

> No. Mirrorly's face data is geometric-shape measurement, not a biometric template. The numbers Mirrorly derives (eye tilt in degrees, jaw angle in degrees, symmetry score on a 0–100 scale, facial-thirds percentages) describe shape ratios; they are not a fixed-length biometric vector that could be used to match the user against another photo or unlock anything. The app does not perform facial recognition, does not call ARKit Face ID, does not authenticate using the user's face, and does not store, transmit, or share a biometric template. The selfie image itself is processed for cosmetic-preview rendering only, by third-party AI APIs (OpenAI, Replicate) under their default no-training, no-retention API terms, and is not retained on Mirrorly's servers.

### "Why do you share Photos with third parties?"

> The selfie image is sent to two API providers solely to deliver core app functionality:
>
> - **OpenAI (GPT-4o Vision)** generates the user's analysis text and "honest" cosmetic rating from the visible face. OpenAI's default API endpoints (which Mirrorly uses) are governed by OpenAI's Enterprise Privacy terms: API inputs are not used to train or improve OpenAI models and are not retained beyond what is required to provide the response.
> - **Replicate (Google Nano Banana + cdingram/face-swap)** renders the "maximized" preview image. Replicate's API terms similarly exclude API inputs from training and provide for transient processing only.
>
> The image is not shared with any other third party — no advertisers, no data brokers, no analytics partners, no SDKs.

### "Data deletion process"

> Mirrorly does not require an account, so all user data is held client-side in the app sandbox. To delete: uninstall the app — iOS and Android automatically delete all sandbox files, including all selfies, generated images, and saved scans. Server-side, the only data Mirrorly briefly handles is the single API request payload (image + geometry numbers) for the seconds it takes to generate the analysis or render; this is auto-expired and never linked to a persistent identifier because no account exists. For written confirmation of deletion or further data requests, email hello@mirrorly.app.

### "Data retention"

> On-device: indefinite, until the user uninstalls. Server-side: none — Mirrorly does not retain a copy of any selfie or any generated image past the single API call that produced it. Transient logs (timestamps, status codes, no image bytes) are kept for a maximum of 30 days for operational diagnostics and then expired.

---

## PART 5 — Privacy Policy / Terms of Use surfacing

The on-device legal screens (`lib/screens/legal/legal_screen.dart`) carry the same content. Reviewers can reach them from:

- The paywall footer ("Privacy Policy" / "Terms of Use" links).
- Settings → Legal.
- Onboarding final step.

Both documents include explicit FACE DATA sections matching the answers above. If a reviewer asks "where does your app explain its face-data handling?" the answer is: *Privacy Policy → "FACE DATA — WHAT IT IS, WHAT IT ISN'T"* and *Terms of Use → "FACE DATA"*.

---

## PART 6 — Quick reference for the App Store / Play submissions

When filling out the forms:

1. **Apple App Privacy** → check only **Photos**, **Other User Content**, and **Purchase History**. All linked. None used for tracking. Purpose: App Functionality.
2. **Apple Tracking** → No.
3. **Play Data Safety → Data Collected**: Other personal info, Purchase history, Photos, Other user-generated content. Mark each as Collected, the photo as Shared (with OpenAI, Replicate, for app functionality), all as Required.
4. **Play Data Safety → Security practices**: Encrypted in transit ✅, Deletion request supported ✅, No commitment to Families policy.
5. **Play biometric question** → No.

That's the full set. There should be nothing left for either reviewer to ask.
