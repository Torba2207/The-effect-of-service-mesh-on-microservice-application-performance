import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import re

# --- 1. Parse IEEE Xplore CSV ---
def parse_ieee(file_path):
    try:
        df = pd.read_csv(file_path)
        title_col = 'Document Title' if 'Document Title' in df.columns else df.columns[0]
        year_col = 'Publication Year' if 'Publication Year' in df.columns else 'Year'
        source_col = 'Publication Title' if 'Publication Title' in df.columns else 'Source'
        
        return pd.DataFrame({
            'Title': df[title_col],
            'Year': df[year_col],
            'Source': df[source_col],
            'Database': 'IEEE'
        })
    except Exception as e:
        print(f"Could not load IEEE: {e}")
        return pd.DataFrame()

# --- 2. Parse Scopus CSV ---
def parse_scopus(file_path):
    try:
        df = pd.read_csv(file_path)
        return pd.DataFrame({
            'Title': df.get('Title', df.iloc[:, 0]),
            'Year': df.get('Year', None),
            'Source': df.get('Source title', None),
            'Database': 'Scopus'
        })
    except Exception as e:
        print(f"Could not load Scopus: {e}")
        return pd.DataFrame()

# --- 3. Parse BibTeX (Primo/Springer) ---
def parse_bibtex(file_path, db_name):
    try:
        records = []
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        entries = re.split(r'@\w+\{', content)[1:]
        
        for entry in entries:
            title_match = re.search(r'title\s*=\s*[\{"](.*?)(?:[\}"]\s*,|\}\s*\n)', entry, re.IGNORECASE | re.DOTALL)
            year_match = re.search(r'year\s*=\s*[\{"]?(\d{4})[\}"]?', entry, re.IGNORECASE)
            # Look for journal, booktitle, publisher, or institution
            source_match = re.search(r'(?:journal|booktitle|publisher|institution)\s*=\s*[\{"](.*?)(?:[\}"]\s*,|\}\s*\n)', entry, re.IGNORECASE | re.DOTALL)
            #source_match = re.search(r'(?:journal|booktitle)\s*=\s*[\{"](.*?)(?:[\}"]\s*,|\}\s*\n)', entry, re.IGNORECASE | re.DOTALL)
            
            records.append({
                'Title': title_match.group(1).replace('\n', ' ').strip() if title_match else None,
                'Year': int(year_match.group(1)) if year_match else None,
                'Source': source_match.group(1).replace('\n', ' ').strip() if source_match else 'Unknown',
                'Database': db_name
            })
        return pd.DataFrame(records)
    except Exception as e:
        print(f"Could not load {db_name}: {e}")
        return pd.DataFrame()

# --- 4. Load and Combine All Data ---
print("Loading data...")
df_ieee = parse_ieee('PaperSources/ieeeXplore_export2026.04.05-11.44.29.csv')
df_scopus = parse_scopus('PaperSources/scopus_export_Apr 4-2026_53efab7f-674e-47a7-8d40-cd0e2255572b.csv')
df_primo = parse_bibtex('PaperSources/Primo_BibTeX_Export.bib', 'arXiv')
df_springer = parse_bibtex('PaperSources/Primo_BibTeX_Export_Spring.bib', 'SpringerLink')
df_acm = parse_bibtex('PaperSources/ACM_Articles.bib', 'ACM Digital Library')

df_all = pd.concat([df_ieee, df_scopus, df_primo, df_springer, df_acm], ignore_index=True)

sns.set_theme(style="whitegrid")

# --- 5. NEW: Pre-deduplication Statistics & Plot ---
print(f"Total articles before deduplication: {len(df_all)}")

plt.figure(figsize=(8, 5))
db_counts = df_all['Database'].value_counts()
ax = sns.barplot(x=db_counts.index, y=db_counts.values, hue=db_counts.index, palette='Set2', legend=False)

# Add exact numbers on top of the bars
for i, v in enumerate(db_counts.values):
    ax.text(i, v + (v * 0.02), str(v), ha='center', va='bottom', fontsize=12, fontweight='bold')

plt.title('Number of Articles per Database (Before Deduplication)', fontsize=14, pad=15)
plt.xlabel('Database', fontsize=12)
plt.ylabel('Number of Articles', fontsize=12)
plt.tight_layout()
plt.savefig('database_counts_pre_dedup.png', dpi=300)
plt.show()

# --- 6. Data Cleaning (Deduplication) ---
# Normalize titles (lowercase, strip whitespace) to find duplicates accurately
df_all['Clean_Title'] = df_all['Title'].astype(str).str.lower().str.strip()
df_all = df_all.drop_duplicates(subset=['Clean_Title'])
df_all['Year'] = pd.to_numeric(df_all['Year'], errors='coerce')

print(f"Total unique articles after deduplication: {len(df_all)}")

# --- 7. Post-Deduplication Visualizations ---
# Plot 2: Publications by Year
plt.figure(figsize=(10, 5))
sns.histplot(data=df_all.dropna(subset=['Year']), x='Year', discrete=True, color='#4C72B0')
plt.title('Number of Unique Publications per Year', fontsize=14, pad=15)
plt.xlabel('Publication Year', fontsize=12)
plt.ylabel('Number of Articles', fontsize=12)
plt.xticks(rotation=45)
plt.tight_layout()
plt.savefig('publications_by_year.png', dpi=300)
plt.show()

# Plot 3: Top 10 Sources (Journals/Conferences)
plt.figure(figsize=(10, 6))
#top_sources = df_all['Source'].value_counts().head(10)
top_sources = df_all[df_all['Source'] != 'Unknown']['Source'].value_counts().head(10)
sns.barplot(y=top_sources.index, x=top_sources.values, hue=top_sources.index, palette='viridis', legend=False)
plt.title('Top 10 Publication Sources (Unique Articles)', fontsize=14, pad=15)
plt.xlabel('Number of Articles', fontsize=12)
plt.ylabel('Journal / Conference Title', fontsize=12)
plt.tight_layout()
plt.savefig('top_sources.png', dpi=300, bbox_inches='tight')
plt.show()

# Optional: Export the cleaned, merged dataset to a new CSV
df_all.drop(columns=['Clean_Title']).to_csv('master_slr_dataset.csv', index=False)
print("Data saved to 'master_slr_dataset.csv' and charts generated!")