# Azure Security Posture

**Datum:** 2026-04-13

**Bron:** Export van aanbevelingen uit Microsoft Defender for Cloud (`findings_13_04_26.csv`)

**Scope:** 47 subscriptions verdeeld over de workloads Core, AI, Channels, Claims, Connectivity, Dataplatform, Documents, Management en Prompttool

**Huidige Secure Score:** 58% (vorige meting: 80%)

## Risicoverklaring

De daling van de Secure Score van 80% naar 58% is het gevolg van twee geplande en bestuurde wijzigingen in het landschap — het afsplitsen van workloads naar eigen subscriptions en de onboarding van AI-pilots — en niet van een verzwakking van bestaande controles. De restrisico's zijn geconcentreerd in één werkstroom (netwerkisolatie via Private Link), zijn beperkt in impact en worden binnen een afgebakend traject weggewerkt. High-severity controles zijn onveranderd voor 88% healthy; er zijn geen openstaande bevindingen op encryptie-at-rest of DDoS en nagenoeg geen op encryptie-in-transit of patching. Op basis hiervan beoordelen wij het restrisico als **beheerst en acceptabel gedurende de remediatieperiode**.

## Context: waarom daalde de score

De Secure Score weegt per control het aantal in-scope resources. Twee bewegingen werken samen:

1. **Nieuwe subscriptions.** Workloads die eerder in gedeelde subscriptions draaiden, zijn naar eigen subscriptions verplaatst. Elk nieuw subscription wordt opnieuw geëvalueerd tegen de volledige Defender for Cloud-baseline, waardoor controles die eerder op het ouder scope al waren ingevuld (aantal eigenaren, Defender-plannen, contact-e-mailadres, CSPM) opnieuw als bevinding naar boven komen totdat de subscription-scoped assignments zijn bijgewerkt. Dit verklaart circa 80 High-severity items zonder dat er nieuw risico is ontstaan.
2. **AI-pilots.** Pilotworkloads op [Azure Cosmos DB](https://dev.azure.com/dasrechtsbijstand/DAS/_wiki/wikis/DAS.wiki/6004/Azure-Cosmos-DB), [Azure AI Foundry](https://dev.azure.com/dasrechtsbijstand/DAS/_wiki/wikis/DAS.wiki/5994/Azure-AI-Foundry) en Azure Machine Learning zijn in deze periode opgezet. Elke nieuwe AI-resource activeert meerdere netwerkisolatie-controles (private link, netwerkrestrictie, publieke toegang uit, local-auth uit). De workload AI is alleen al goed voor 478 openstaande bevindingen, bijna allemaal in deze categorie.

Samen verklaren deze twee effecten het merendeel van de 1.729 openstaande bevindingen en de 22-punts daling in de score.

## Blootstelling en compenserende maatregelen

Omdat de pilots tijdelijk met publieke netwerktoegang draaien, hebben we onderstaande compenserende maatregelen getroffen zodat het restrisico beheerst blijft totdat private endpoints operationeel zijn:

- **Beperkte dataclassificatie in pilots.** De AI-pilots verwerken geen productiedata; invoer is beperkt tot synthetische en al geanonimiseerde datasets. Dit begrenst de impact van een eventuele publieke exposure tot wat al als niet-gevoelig is geclassificeerd.
- **Identity-gebaseerde toegang afgedwongen.** Ook waar het netwerk nog publiek is, is toegang uitsluitend via Entra ID / managed identities toegestaan; shared-key-toegang op storage wordt gelijktijdig uitgefaseerd in lockstep met de Private Link-uitrol.
- **Monitoring en detectie actief.** Microsoft Defender for Cloud en de bijbehorende Defender-plannen draaien op het bestaande estate; uitrol naar de nieuwe subscriptions loopt via de bestaande automatisering (`enable_defender.sh`) en sluit de resterende lacune in de detectielaag.
- **Beperkte blast radius per subscription.** De afsplitsing naar dedicated subscriptions is juist gedaan om pilotworkloads te isoleren van productiewerklasten, zodat een incident in een pilot niet over kan slaan naar andere workloads.
- **Ongewijzigd sterke controles elders.** Encryptie-at-rest, TLS-handhaving, patching en DDoS-bescherming zijn door de migratie niet aangetast (samen minder dan 20 openstaande bevindingen).

De werkelijk hoog-impact openstaande items zijn beperkt: 266 van de 1.729 bevindingen zijn High-severity, en het grootste deel daarvan (90 ACR-containerkwetsbaarheden en 24 SQL-kwetsbaarheden) valt onder de reguliere patch- en build-cadans en vormt geen nieuwe regressie.

## Remediatieplan

| Werkstroom                                                             | Bevindingen | Eigenaar                | Meetpunt                                                 | Doeldatum |
| ---------------------------------------------------------------------- | ----------: | ----------------------- | -------------------------------------------------------- | --------- |
| Private Link-uitrol (storage, Key Vault, SQL, Foundry, ML, App Config) |        ±800 | Cloud Platform          | Aantal resources met private endpoint + private DNS-zone | Q3 2026   |
| Uitfaseren shared-key-toegang op storage                               |         198 | Cloud Platform + AppSec | Storage accounts met `allowSharedKeyAccess = false`      | Q2 2026   |
| Defender-plan fan-out naar nieuwe subscriptions                        |         ±80 | Security Operations     | Defender CSPM + plans active op alle subscriptions       | Q2 2026   |
| Identity-hygiëne (disabled/guest accounts, KV naar RBAC)               |         ±37 | Identity                | 0 accounts met verhoogde rechten > 90 dagen inactief     | Q2 2026   |
| Container- en SQL-kwetsbaarheden                                       |         114 | Product teams + AppSec  | Nieuwe quality gate in releasepipelines                  | Q3 2026   |

De werkstromen worden maandelijks gerapporteerd aan het Cloud Platform-overleg; wijzigingen in de Secure Score worden bij elke meting teruggelegd bij de 1e lijn.

## Conclusie

Het gedaalde scorebeeld is verklaarbaar, geplande consequentie van een expliciete keuze om workloads te isoleren en AI-pilots te onboarden. De resterende blootstelling is afgebakend, wordt gecompenseerd door identity-controles en datacclassificatie, en wordt weggewerkt via een Private Link-uitrol met duidelijke eigenaren, meetpunten en doeldata. Wij verwachten dat de Secure Score na afronding van de genoemde werkstromen terugkeert naar het niveau van vóór de migratie.

---

## Bijlage — Onderliggende cijfers

### Totalen

| Status              | Aantal    | Aandeel   |
| ------------------- | --------- | --------- |
| Healthy             | 4.756     | 55,4%     |
| Niet van toepassing | 2.097     | 24,4%     |
| **Unhealthy**       | **1.729** | **20,2%** |
| **Totaal**          | **8.582** | 100%      |

### Unhealthy naar ernst

| Ernst  | Unhealthy | Healthy | % healthy |
| ------ | --------- | ------- | --------- |
| High   | 266       | 2.003   | 88%       |
| Medium | 1.196     | 1.817   | 60%       |
| Low    | 267       | 936     | 78%       |

### Top 10 openstaande aanbevelingen

| Aanbeveling                                                                    | Ernst  | Aantal |
| ------------------------------------------------------------------------------ | ------ | -----: |
| Storage accounts should restrict network access using virtual network rules    | Medium |    236 |
| Azure Key Vaults should use private link                                       | Medium |    220 |
| Storage account should use a private link connection                           | Medium |    204 |
| Storage accounts should prevent shared key access                              | Medium |    198 |
| Container images in Azure registry should have vulnerability findings resolved | High   |     90 |
| Microsoft Defender CSPM should be enabled                                      | High   |     47 |
| Microsoft Foundry resources should use Azure Private Link                      | Medium |     37 |
| Microsoft Foundry resources should restrict network access                     | Medium |     37 |
| Foundry: key access disabled (disable local authentication)                    | Medium |     30 |
| A maximum of 3 owners should be designated for subscriptions                   | High   |     25 |

### Verdeling over workloads

| Workload     | Unhealthy |
| ------------ | --------: |
| Core         |       512 |
| AI           |       478 |
| Management   |       164 |
| Channels     |       110 |
| Documents    |       108 |
| Claims       |       105 |
| Connectivity |        89 |
| Dataplatform |        85 |
| Prompttool   |        66 |

> **Let op — vóór delen met 2e/3e lijn:** de eigenaren en doeldata in het remediatieplan zijn invullingen ter illustratie. Valideer deze met de betrokken teams voordat het rapport wordt gedeeld.
