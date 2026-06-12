#align(left)[
  #image("images/Logo_pg_eti.png", width: 60%)
]

#align(horizon)[
#align(center)[#text(size: 20pt)[= Wpływ rozwiązań service mesh na efektywność działania aplikacji mikrousługowych]]
#align(center)[#text(size: 18pt)[== Harmonogram 1.2]]
#align(center)[#text(size: 16pt)[=== Oleksandr Nychyporchuk, Alla Krylova, Kiryl Pashkevich, Pavel Khmialeuski]]]
#pagebreak()

#table(
  columns: (0.8fr, 3fr, 3fr),
  align: (center + horizon, left, left),
  
  [Termin], [#align(center)[*Cel*]], [#align(center)[*Oczekiwane pliki*]],
  
  
  
  [08.04.2026], [Papierowy prototyp aplikacji mikrousługowej], [Plik PDF z ogólnym opisem aplikacji i wykazem mikrousług, z których się składa],
  
  [11.04.2026], [Opis planowanej architektury środowiska oraz określenie optymalnych zasobów dla zabezpieczenia stabilnej pracy aplikacji], [Plik PDF z opisem planowanej architektury oraz zdefiniowanymi wymaganiami zasobowymi wraz z uzasadnieniem],
  
  [04.05.2026], [Konfiguracja środowiska na przydzielonych maszynach wirtualnych], [Krótki raport PDF z potwierdzeniem działania klastra oraz skrypty konfiguracyjne],
  
  [04.05.2026], [Implementacja n wybranych mikrousług aplikacji i ich wdrożenie], [Kod źródłowy mikrousług (link do repozytorium) oraz manifesty wdrożeniowe],
  
  [10.05.2026], [Pilotażowe badania wydajności bez użycia service mesh], [Raport PDF z wynikami pomiarów bazowych (np. opóźnienia, przepustowość, zużycie CPU/RAM) i surowe logi z testów],
  
  [30.09.2026], [Pomiary wydajności z użyciem różnych rozwiązań service mesh], [Raport PDF z wynikami dla różnych rozwiązań service mesh oraz pliki konfiguracyjne],
  
  [30.09.2026], [Podsumowanie pomiarów wydajności, wnioskowanie], [Ostateczny raport PDF z zestawieniem wyników (tabele, wykresy porównawcze) i wnioskami],

  [30.10.2026], [Badanie zorientowane na opóźnienia], [Zbadanie zachowania mikroserwisów w warunkach gdzie wielu małych usług wymieniających częste, niemal puste żądania, z symulowanym opóźnieniem między węzłami, aby scharakteryzować, jak zachowuje się każdy data plane, gdy narzut związany z proxy/szyfrowaniem dominuje nad payload, a nie nad obliczeniami.]

  
)
