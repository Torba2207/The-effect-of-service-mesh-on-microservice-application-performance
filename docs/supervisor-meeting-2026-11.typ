#set page(paper: "a4", margin: (x: 2.2cm, y: 2.2cm), numbering: "1")
#set text(font: "Linux Libertine", size: 11pt, lang: "pl")
#set heading(numbering: "1.1")
#set par(justify: true)

#align(center)[
  #text(size: 17pt, weight: "bold")[Punkty do omówienia z promotorem] \
  #v(0.3em)
  #text(size: 11pt)[Stan prac, otwarte decyzje i propozycje — listopad 2026] \
  #v(0.3em)
  #text(size: 10pt, style: "italic")[Szczegóły: docs/test-scenario.typ (uwagi o Consulu i AI), docs/messaging-topology-plan.typ (faza C)]
]
#v(1em)

= Decyzje do podjęcia

#figure(
  table(
    columns: (auto, 1fr, 1fr),
    fill: (x, y) => if y == 0 { luma(235) } else { none },
    inset: 6pt, align: (left + top, left + top, left + top),
    [*\#*], [*Pytanie*], [*Nasza propozycja*],
    [D1], [Consul: ACL wyłączone, jawne intentions „allow-all” — czy to akceptowalne?], [Tak; ACL nie wpływają na opóźnienia, a bez nich konfiguracja jest symetryczna z Istio i Linkerd.],
    [D2], [Wejście do klastra dla Consula: API Gateway czy NGINX w meshu (jak dla Linkerd)?], [Otwarte — gateway to natywne rozwiązanie Consula, NGINX daje symetrię z L-S (§3).],
    [D3], [Przez API Gateway Consula nie da się zmierzyć komórki `ai` S1. Jak to rozwiązać?], [Pominąć tę komórkę dla C-S z wyraźnym zastrzeżeniem; terminating gateway tylko wtedy, gdy wymagana jest pełna macierz. Jeśli zostanie przyjęte D6, problem znika: host AI w katalogu Consula jest osiągalny przez gateway.],
    [D4], [Czy konfiguracja C-P istnieje i czym ma być?], [Ominięcie proxy, jak L-P; wymaga najpierw decyzji D2 (ominięcie psuje routing przez API Gateway).],
    [D5], [Wersja TLS: Consul wynegocjował TLS 1.2. Czy ujednolicić wersje między meshami przed porównaniem kosztu szyfrowania?], [Sprawdzić, co negocjują Istio i Linkerd; ujednolicić, jeśli się różnią.],
    [D6], [Dodać scenariusz „host AI wewnątrz meshu”? Bez tras do podów wykonalny tylko dla Istio i Consula. Dla Linkerd: trasy statyczne na hoście AI czy BGP z Calico?], [Tak, jako uzupełnienie (nie zamiennik): Istio, Consul, potem Linkerd z trasami statycznymi (bez zmian w klastrze, dane pozostają porównywalne). BGP tylko, jeśli promotor woli trwałe rozwiązanie po stronie klastra.],
    [D7], [Faza C: narzędzie, polityka ponowień, skala, wartości symulowanego opóźnienia między węzłami], [§5.],
    [D8], [Dryf między kampaniami (filters→ai: I-P wolniejsze niż I-S) — powtórzyć czy przeplatać powtórzenia?], [Powtórzyć tę parę jedna po drugiej; w nowych kampaniach wprowadzić przeplatanie.],
    [D9], [Czy S2-amp i pomiar w stanie bezczynności są nadal potrzebne?], [Zostawić S2-amp (najsilniejsza próba ścieżki mesh→mesh); pomiar bezczynności opcjonalny.],
    [D10], [Nowe terminy dla kamieni milowych 30.09 i 30.10], [Uzgodnić poprawiony harmonogram dla rozszerzonej macierzy i fazy C (§6).],
  ),
  caption: [Zestawienie decyzji, które chcielibyśmy podjąć na spotkaniu.],
)

= Stan prac (do wiadomości)

- *Faza A, podstawowa macierz ukończona:* 45/45 komórek — 9 scenariuszy × 5 konfiguracji (B, L-P,
  L-S, I-P, I-S), każda 3 poziomy obciążenia × 10 powtórzeń, 0 nieudanych przebiegów. Brakuje
  jeszcze: S2-amp (nie ma skryptu k6) i pomiaru w stanie bezczynności (nie ma skryptu
  uruchamiającego).
- *Faza B:* zmierzone wszystkie 5 podstawowych konfiguracji.
- *Consul (C-S):* wdrażany przez `make consul` (Helm, Consul 2.0.4), sprawdzony na klastrze;
  oznaczony jako wstępny do czasu tego przeglądu. Skrypty testowe i kolektor metryk nie obsługują
  jeszcze Consula.
- *Istio Ambient (A-L4, A-W):* nierozpoczęte; najpierw kolektor musi obsługiwać `ztunnel`
  działający na każdym węźle.
- *Wydajność AI rozwiązana:* nowy host z GPU (RTX 4070) obsługuje ≈ 12 zapytań/s; wcześniejszy
  limit maszyny bez GPU (≈ 0,3–1 zapytania/s) nie ogranicza już projektu testów.
- *Infrastruktura:* wdrożenia i kampanie mogą teraz działać w całości na generatorze obciążenia,
  więc kampania nie zależy już od połączenia VPN stacji roboczej.

= Wyniki do interpretacji

+ *Koszt meshu na łańcuchach do zewnętrznego hosta AI jest mały:* 0–3 ms, poniżej 1,5 % czasu
  odpowiedzi; dominuje inferencja na GPU.
+ *permutation→ai, średnie obciążenie:* przeskok przez Envoy +1,3 ms, mTLS w Istio +1,1 ms, mTLS w
  Linkerd (L-S − L-P) +2,9 ms. Zastrzeżenie: L-P to ominięcie proxy, a nie wyłączenie szyfrowania,
  więc wartość dla Linkerd obejmuje też samo proxy.
+ *`ai` S1:* wszystkie pięć konfiguracji mieści się w 2,5 ms.
+ *Pomiar w izolacji zaniża koszt meshu:* w fazie A (jeden endpoint naraz) przeskok przez Linkerd
  na filters jest prawie darmowy aż do wysokiego obciążenia; w fazie B (wszystkie usługi obciążone
  jednocześnie) kosztuje +1,0–1,3 ms na każdym poziomie.
+ *Ranking w fazie B zależy od obciążenia:* Istio wygrywa z Linkerd na lekkich usługach, ale
  przegrywa na video.

Pytania:

- *Dryf między kampaniami (D8).* Dla filters→ai konfiguracja I-P wyszła wolniejsza niż I-S, więc
  kosztu mTLS w Istio nie da się wyznaczyć; obie komórki mierzono w różnych kampaniach. Powtórzyć
  tę parę jedna po drugiej, czy przyjąć i opisać jako mieszczące się w dryfie między przebiegami?
- *Postępowanie z wartościami odstającymi.* Jeden przebieg I-P filters→ai (high, r7) ma p50
  521,6 ms wobec 502,0 ± 0,7 ms dla pozostałych. Raportujemy go i nie odrzucamy — czy tak ma być?
- *Opis L-P:* raportowane jako „ominięcie proxy”, nigdy jako „Linkerd bez mTLS”. Zgoda?

= Przegląd konfiguracji Consula (C-S)

Consul różni się od Istio i Linkerd tym, że nie powstał z myślą przede wszystkim o Kubernetesie:
jego serwery przechowują własny stan (Raft, katalog usług, CA) na trwałym wolumenie, usługi
Kubernetesa są kopiowane do tego katalogu, a autoryzacja to osobna warstwa (intentions).

- *D1 — bez ACL.* Intentions „allow-all” (`ServiceIntentions`) zapisane jawnie.
- *D2 — wejście.* Obecnie Consul API Gateway (osobny Envoy, najbliższy bramie Istio). L-S wchodzi
  przez NGINX w meshu; to samo dla Consula dałoby symetryczne porównanie, ale wtedy NGINX musi
  pomijać przechwytywanie swoich portów wejściowych, bo sidecar Consula przyjmuje tylko mTLS.
  Z tego samego powodu pod Consulem nie działają bezpośrednie NodePorty usług (sprawdzone).
- *D3 — brak `ai` S1.* Gateway kieruje ruch tylko do usług z katalogu Consula; host AI to
  zewnętrzna maszyna wirtualna, więc nie ma trasy `/api/Ai`. Opcje: (a) zarejestrować host AI jako
  usługę zewnętrzną za terminating gateway — dodaje przeskok przez Envoy, którego nie mają inne
  meshe; (b) kierować tylko `/api/Ai` przez NGINX — inny punkt wejścia dla jednej komórki;
  (c) pominąć tę komórkę dla C-S. Łańcuchy S2-ext działają (docierają do hosta AI przez sidecary
  samych usług).
- *D4 — C-P.* mTLS w Consulu nie da się wyłączyć (jak w Linkerd), więc C-P byłoby ominięciem
  proxy. Przy API Gateway, który do usług zawsze mówi przez mTLS, ominięcie nie jest możliwe.
- *D5 — wersja TLS.* mTLS między gatewayem a usługami użyło domyślnie TLS 1.2
  (ECDHE-ECDSA-AES128-GCM-SHA256).
- *Do wiadomości:* jedna replika serwera z wolumenem 2 GB; klaster nie miał żadnej StorageClass,
  więc instalowany jest `local-path-provisioner` (bezczynny podczas pomiarów, ale to dodatkowy
  komponent, którego nie mają inne konfiguracje); wersja chartu przypięta do 2.0.4; CRD Gateway API
  współdzielone z Istio.

= Propozycja: host AI wewnątrz meshu (D6)

Obecnie host AI jest zależnością zewnętrzną we wszystkich konfiguracjach: usługi łączą się z nim
otwartym tekstem przez passthrough sidecara, a na samej maszynie nic nie działa. Włączenie go do
meshu dałoby mu własną tożsamość, mTLS na ostatnim przeskoku i własne proxy wejściowe. To, że jest
to maszyna fizyczna, a nie wirtualna, nie ma znaczenia: „VM” w dokumentacji wszystkich trzech meshy
oznacza dowolny host Linux poza klastrem.

== Co ustaliliśmy o sieci

Sprawdzone 04.11.2026 (dokumentacja meshy + konfiguracja klastra; na hoście AI nic jeszcze nie
instalowano):

- Calico działa w trybie `vxlanMode: Always` z `natOutgoing: true` — adresy IP podów nie są
  osiągalne spoza klastra, a ruch podów wychodzący z klastra jest maskowany adresem węzła.
- Pody docierają do hosta AI (10.29.20.121), host AI dociera do adresów węzłów, ale nie ma trasy do
  podów ani usług. Zapora na hoście AI jest wyłączona.
- Usługa AI tylko *przyjmuje* wywołania z klastra; sama nie wywołuje niczego w klastrze. Dlatego
  potrzebny jest tylko kierunek pod → host, a ten działa.

== Wnioski dla każdego meshu

- *Istio — wykonalne bez zmian w sieci.* Host łączy się z istiod przez bramę east–west, pody łączą
  się z hostem bezpośrednio. Zastrzeżenia: pakiet sidecara jest wydawany dla Debiana i CentOS 8
  (Ubuntu 24.04 wywodzi się z Debiana, ale nie jest wymienione), a bez LoadBalancera bramę east–west
  trzeba wystawić przez NodePort lub `externalIPs`, co odbiega od opisanej konfiguracji.
- *Consul — wykonalne bez zmian w sieci.* Agent klienta Consula + Envoy na hoście. Consul opisuje
  tryb dokładnie dla naszego przypadku (IP podów nieosiągalne, IP węzłów osiągalne): serwery
  wystawiają porty gossip i RPC jako hostPort; nasz chart to obsługuje. Zmienia to konfigurację
  serwerów C-S, ale nie data plane. Połączenie „agent na hoście + instalacja oparta na
  consul-dataplane + TLS Consula” nie jest opisane w jednym miejscu i wymaga testu. Dodatkowa
  korzyść: po rejestracji hosta w katalogu API Gateway mógłby kierować ruch do `/api/Ai`, co
  rozwiązuje D3.
- *Linkerd — niewykonalne w obecnej sieci; wykonalne po dodaniu tras na hoście AI.* Dokumentacja
  wymaga łączności IP z maszyny do każdego poda w meshu (sieć „płaska”) oraz DNS na maszynie
  rozwiązującego nazwy z klastra; do tego SPIRE dla tożsamości i ręcznie napisane reguły
  iptables. Dziś warunki sieciowe nie są spełnione — sposoby ich spełnienia opisuje następna
  sekcja.

== Jak udostępnić sieć podów hostowi AI (tylko dla Linkerd)

Stan sprawdzony 04.11.2026: Calico v3.30.6 zainstalowany przez Kubespray z `calico_backend:
vxlan`, więc BIRD (demon BGP Calico) nie działa; `BGPConfiguration` istnieje (AS 64512, siatka
węzeł–węzeł włączona), ale bez BIRD nic nie robi; `BGPPeer` brak. Każdy z sześciu węzłów ma jeden
blok /26 z puli podów (node1 10.233.102.128/26, node2 10.233.75.64/26, node3 10.233.71.0/26, node4
10.233.74.64/26, node5 10.233.97.128/26, node6 10.233.75.0/26). Sieć usług: 10.233.0.0/18 (CoreDNS
10.233.0.3). Węzły (10.29.20.101–103, .111–113) i host AI (.121) są w jednej podsieci, więc host
AI może wysyłać ruch do poda prosto na węzeł, który go hostuje, bez tunelu.

Warianty, od najmniej inwazyjnego:

+ *Trasy statyczne na hoście AI, po jednej na węzeł* (bez zmian w klastrze): `ip route add <blok>
  via <IP węzła>`, generowane skryptem z `blockaffinities` przed każdą kampanią (bloki mogą się
  zmieniać). Odpowiedź wraca przez ten sam węzeł (połączenie otwiera host AI, więc `natOutgoing`
  nie działa) — trasa jest symetryczna. Jedna trasa na całe /18 przez jeden węzeł raczej nie
  zadziała: odpowiedzi z podów na innych węzłach wracałyby inną drogą, a Calico może odrzucać
  taki asymetryczny ruch (przypuszczenie, nie testowane). Dla DNS: trasa do 10.233.0.0/18 przez
  dowolny węzeł (kube-proxy tłumaczy adres usługi) — powinno działać, wymaga testu.
+ *Peering BGP hosta AI z Calico.* (a) Przełączyć backend Calico na BIRD, *zostawiając*
  `vxlanMode: Always` (Kubespray: `calico_network_backend: bird` i ponowne uruchomienie z `--tags
  network`; ręczna zmiana ConfigMapy zostałaby cofnięta przy następnym przebiegu Kubespray).
  (b) `nodeToNodeMeshEnabled: false` — przy VXLAN trasy między węzłami programuje Felix z IPAM, a
  bez siatki każdy węzeł ogłasza tylko własny blok, więc host AI zawsze dostaje „blok → węzeł
  właściciel”. (c) Globalny `BGPPeer` dla 10.29.20.121 (przez `calicoctl`, API server Calico nie
  jest zainstalowany). (d) FRR na hoście AI: przyjmuje tylko 10.233.64.0/18 i dłuższe prefiksy,
  niczego nie ogłasza. Opcjonalnie `serviceClusterIPs: 10.233.0.0/18` w `BGPConfiguration` —
  wtedy host widzi też adresy usług, w tym DNS klastra. Ścieżka pakietów taka sama jak w wariancie
  1, ale trasy aktualizują się same. Zmiana backendu restartuje `calico-node` na wszystkich
  węzłach; wymaga zgody i dostępu do inwentarza Kubespray.
+ *Routing bez enkapsulacji* (`vxlanMode: Never` + BGP): możliwy (wspólny segment L2), ale zmienia
  ścieżkę ruchu pod → pod między węzłami. Odrzucony (niżej).

Istnieje też skrót nieopisany w dokumentacji: host AI nie wywołuje niczego w klastrze, więc jego
proxy potrzebuje tylko control plane Linkerd (destination i policy; tożsamość daje SPIRE).
Wystawienie ich przez NodePort i wskazanie adresów proxy (`LINKERD2_PROXY_DESTINATION_SVC_ADDR`,
`LINKERD2_PROXY_POLICY_SVC_ADDR`) mogłoby działać bez żadnych tras. Nietestowane.

*Ważność porównań.* Warianty 1 i 2 przy `vxlanMode: Always` nie zmieniają żadnej mierzonej
ścieżki: pod → pod między węzłami nadal idzie przez VXLAN, pod → host AI nadal przez NAT na adres
węzła. Nowe trasy obsługują tylko połączenia otwierane z hosta AI (ruch sterujący proxy, DNS), a
BIRD wymienia jedynie trasy. Dotychczasowe dane B, I-S, I-P, L-S, L-P pozostają porównywalne
z nowymi. Po wariancie 2 (restart `calico-node`) warto zrobić krótki kontrolny przebieg baseline
(S1 i S2-int) i sprawdzić, czy wyniki mieszczą się w dotychczasowym rozrzucie. Wariant 3 usuwa
narzut VXLAN i zmienia MTU na każdym przeskoku między węzłami (także w S2-int) — całą macierz
trzeba by mierzyć od nowa, więc go nie proponujemy.

== Skutki dla eksperymentu

- *Zakres porównania:* bez żadnych tras scenariusz obejmuje tylko Istio i Consula. Trasy statyczne
  na hoście AI dodają Linkerd bez zmian w klastrze; BGP robi to samo, ale zmienia konfigurację
  Calico. Pytanie do promotora: dwa meshe, trasy statyczne czy BGP?
- *Szum:* narzut proxy (kilka ms) jest mały wobec ok. 500 ms inferencji, więc komórki tego
  scenariusza trzeba mierzyć z przeplataniem konfiguracji (D8), nie w osobnych kampaniach.
- *Ponowne pomiary:* łańcuchy S2-ext stają się „mesh → usługa w meshu”. Wszystkie komórki AI
  w konfiguracjach z meshem (12 w fazie A oraz część AI w fazie B) trzeba by zmierzyć ponownie;
  baseline się nie zmienia.
- *Wartość:* jako dodatkowy scenariusz pokazuje, jak koszt meshu różni się przy wywołaniu usługi
  zewnętrznej i usługi w meshu; istniejące dane pozostają ważne.
- *Ryzyko:* Docker na hoście GPU sam modyfikuje iptables dla opublikowanych portów, a proxy Istio
  i Linkerd przechwytują ruch też przez iptables — trzeba to przetestować razem. Envoy Consula na
  hoście domyślnie nie przechwytuje ruchu (nasłuchuje na własnym porcie i przekazuje do
  `localhost:5005`), więc tam ryzyko jest najmniejsze.
- *Nakład pracy:* ok. jeden dzień dla Istio i jeden dla Consula; ok. dwa dni dla Linkerd z trasami
  statycznymi (SPIRE i ręczne iptables), oszacowanie mniej pewne.

= Faza C — badanie zorientowane na opóźnienia (D7)

Harmonogram (30.10.2026) przewiduje wiele małych usług wymieniających częste, niemal puste żądania
*z symulowanym opóźnieniem między węzłami*, aby sprawdzić, jak zachowuje się każdy data plane, gdy
dominuje narzut proxy i szyfrowania. Szkic planu: `docs/messaging-topology-plan.typ` — jedna
minimalna usługa przekazująca wdrożona wielokrotnie; łańcuchy (głębokość 1–16), fan-out (2–32)
i skala (10–100 bezczynnych usług); metryki: opóźnienie (w tym koszt pojedynczego przeskoku jako
nachylenie względem głębokości łańcucha) i straty (błędy, przekroczenia czasu, ponowienia ukryte
przez mesh, zlokalizowane na konkretnym przeskoku).

Pytania:

- *Symulowanego opóźnienia między węzłami* brakuje w szkicu. Propozycja: opóźnienie `tc netem` na
  interfejsach węzłów roboczych, np. 0 / 1 / 5 ms. Jakie wartości (i czy z jitterem)?
- *Narzędzie:* isotope (generator topologii z projektu Istio) czy własna mała usługa przekazująca?
- *Ponowienia:* zostawić domyślne ustawienia każdego meshu (Istio ponawia część błędów, Linkerd nie)
  i raportować liczniki ponowień, czy wyłączyć ponowienia wszędzie, aby straty były bezpośrednio
  porównywalne?
- *Skala:* czy 100 usług z sidecarami jest realne na 3 węzłach roboczych, czy granicą jest 50?
- *Zakres:* uwzględnić Consula? Tylko HTTP/1.1, czy także gRPC?
- *Budżet:* 5 konfiguracji × 11 topologii × 3 poziomy obciążenia × n = 10 ≈ 41 h obciążenia na
  jeden rozmiar payloadu, jeszcze przed pomnożeniem przez poziomy opóźnienia. Które wymiary
  ograniczyć, skoro liczba powtórzeń zostaje 10?

= Harmonogram i infrastruktura

- *Kamienie milowe (D10):* harmonogram przewidywał pomiary meshy i raport końcowy na 30.09.2026
  oraz badanie zorientowane na opóźnienia na 30.10.2026. Macierz urosła od tego czasu z 5 do 9
  konfiguracji (Consul i Istio Ambient), a faza C jest wciąż na etapie planu — chcielibyśmy
  uzgodnić nowe terminy.
- *Rozmiar dysków maszyn:* dyski 25 GB zainstalowano z zaledwie 11 GB na główny system plików. Na
  generatorze obciążenia już rozszerzone (a wcześniej na węzłach roboczych); trzy węzły
  control-plane mają nadal 11 GB i są zapełnione w ok. 80 %, blisko progu, przy którym Kubernetes
  zaczyna usuwać pody. Czy możemy je rozszerzyć (w trakcie pracy, bez restartu)?
- *Generator obciążenia jako host kampanii:* będzie przechowywał kubeconfig z uprawnieniami
  administratora klastra oraz klucz SSH akceptowany przez węzły klastra. Czy jest to zgodne
  z zasadami korzystania z tych maszyn?
