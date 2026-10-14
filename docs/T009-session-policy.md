# T009 — orari dhe identiteti i ditës

SessionPolicy.mqh merr UTC të furnizuar; nuk lexon orën, llogarinë ose tregtitë. Llogarit orën civile Europe/Tirane, offset-in verë/dimër, day_key YYYYMMDD dhe momentin UTC të mesnatës lokale. Nuk fshin numërues ose gjendje llogarie.

Parazgjedhjet e klientit: e hënë–e premte, 00:00–20:30; e premte21:00 kërkesë mbylljeje. Konventa teknike: fillimi përfshihet, fundi jo; në21:00 flag-uFriday bëhet true. Kufijtë janë inpute. Vetëm intervale brenda ditës; overnight refuzohet. cancel_pending_due do të thotë hyrjet jashtë seancës janë të mbyllura, jo komandë e dërguar. Pozicionet në fundin normal20:30 mbeten çështje më vete; Friday21 flag-u është vetëm të premten, pa catchup të fundjavës.

SP_DayChanged krahason dy UTC monotone dhe day_key; inputet mbrapsht ose jashtë intervalit të mbështetur refuzohen. Nuk pretendon reset persistent ose numërim fitimesh/humbjesh.

Rregulli aktual IANA për Shqipërinë: UTC+1 dimër, UTC+2 verë; ndryshimi të dielën e fundit të marsit/tetorit në01:00UTC. Implementimi kufizohet në vite UTC/lokale1996–2099 dhe përdor këtë përsëritje; nuk garanton se ligji i ardhshëm nuk ndryshon. Përpara1996 refuzohet, sepse historia ndryshon. Shembujt historikë duhet të furnizojnë UTC reale, jo orën e serverit e emërtuar UTC.

EA preview v1.02 shton InpSessionSource: SESSION_MANUAL (parazgjedhje, sjellja e vjetër) ose SESSION_TIRANE_CLOCK. Në auto përdoret TimeGMT, që varet nga ora/konfigurimi i kompjuterit; logu T009 SESSION shfaq UTC/Tirane/day/midnight për kontroll. Në Strategy Tester ky burim refuzohet sepse TimeGMT atje është ora e simuluar e serverit. Burimi automatik zëvendëson vetëm portën e seancës; lajmet, spread-i, sinjali dhe ekspozimi mbeten të jashtme. Preview është statik në OnInit, jo monitor automatik i orarit.

Prova: fillimisht T009_SessionTest nga Scripts. Pastaj preview EA me inputet e T008 dhe InpSessionSource=SESSION_TIRANE_CLOCK; dërgo T009 SESSION dhe T008 PREVIEW. Jashtë20:30 pritet SESSION_CLOSED. Asnjë flag nuk dërgon/anulon/mbyll urdhra.

Burime: [IANA Europe/Tirane + EU rules](https://data.iana.org/time-zones/tzdb/europe), [TimeGMT dhe kufiri në tester](https://www.mql5.com/en/docs/dateandtime/timegmt).
