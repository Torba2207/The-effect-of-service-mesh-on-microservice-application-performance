#align(left)[
  #image("images/Logo_pg_eti.png", width: 60%)
]

#align(horizon)[
#align(center)[#text(size: 20pt)[= Wpływ rozwiązań service mesh na efektywność działania aplikacji mikrousługowych]]
#align(center)[#text(size: 18pt)[== Harmonogram 0.1]]
#align(center)[#text(size: 16pt)[=== Oleksandr Nychyporchuk, Alla Krylova, Kiryl Pashkevich, Pavel Khmialeuski]]]
#pagebreak()

#table(
  columns: (0.8fr, 3fr, 3fr),
  align: (center + horizon, left, left),
  
  [Termin], [#align(center)[*Cel*]], [#align(center)[*Oczekiwane pliki*]],
  
  [31.03.2026], [Formowanie bazy wiedzy (service mesh, k8s, containers, microservices)], [Plik PDF z wymienionymi źródłami i krótkim opisem każdego],
  
  [08.04.2026], [Papierowy prototyp aplikacji mikrousługowej], [Plik PDF z ogólnym opisem aplikacji i wykazem mikrousług, z których się składa],
  
  [11.04.2026], [Opis planowanej architektury środowiska oraz określenie optymalnych zasobów dla zabezpieczenia stabilnej pracy aplikacji], [Plik PDF z opisem planowanej architektury oraz zdefiniowanymi wymaganiami zasobowymi wraz z uzasadnieniem],
  
  [25.04.2026], [Konfiguracja środowiska na przydzielonych maszynach wirtualnych], [Krótki raport PDF z potwierdzeniem działania klastra oraz skrypty konfiguracyjne],
  
  [30.04.2026], [Implementacja n wybranych mikrousług aplikacji i ich wdrożenie], [Kod źródłowy mikrousług (link do repozytorium) oraz manifesty wdrożeniowe (np. pliki YAML dla Kubernetes)],
  
  [10.05.2026], [Pilotażowe badania wydajności bez użycia service mesh], [Raport PDF z wynikami pomiarów bazowych (np. opóźnienia, przepustowość, zużycie CPU/RAM) i surowe logi z testów],
  
  [20.05.2026], [Linkerd - pomiary wydajności], [Raport PDF z wynikami dla Linkerd oraz pliki konfiguracyjne użyte do wdrożenia tego mesh'a],
  
  [25.05.2026], [Istio - pomiary wydajności], [Raport PDF z wynikami dla Istio oraz pliki konfiguracyjne],
  
  [30.05.2026], [Consul - pomiary wydajności], [Raport PDF z wynikami dla Consul oraz pliki konfiguracyjne],
  
  [05.06.2026], [Podsumowanie pomiarów wydajności, wnioskowanie], [Ostateczny raport PDF z zestawieniem wyników (tabele, wykresy porównawcze) i końcowymi wnioskami projektowymi]
)
