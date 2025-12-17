import streamlit as st
import yfinance as yf
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import os
from PIL import Image

try:
    img = Image.open("icon/icon.ico")
except Exception:
    img = "📈"  # Icône de secours si le fichier n'est pas trouvé

# --- 1. CONFIGURATION DE LA PAGE ---
st.set_page_config(
    page_title="Mon Portefeuille - BlueChip",
    page_icon=img,
    layout="wide"
)

# Fichiers de sauvegarde
PORTFOLIO_FILE = "portfolio_save.csv"
CASH_FILE = "cash_save.txt"
CAPITAL_FILE = "capital_save.txt"

# --- 2. PERSISTANCE DES DONNÉES ---
def save_all():
    st.session_state.portfolio.to_csv(PORTFOLIO_FILE, index=False)
    with open(CASH_FILE, "w") as f:
        f.write(str(st.session_state.cash))
    with open(CAPITAL_FILE, "w") as f:
        f.write(str(st.session_state.total_invested))

def load_all():
    df = pd.read_csv(PORTFOLIO_FILE) if os.path.exists(PORTFOLIO_FILE) else pd.DataFrame(columns=['Ticker', 'Quantité', 'Prix Achat ($ ou €)'])
    cash = float(open(CASH_FILE, "r").read()) if os.path.exists(CASH_FILE) else 0.0
    capital = float(open(CAPITAL_FILE, "r").read()) if os.path.exists(CAPITAL_FILE) else 0.0
    return df, cash, capital

# Initialisation au démarrage
if 'portfolio' not in st.session_state:
    st.session_state.portfolio, st.session_state.cash, st.session_state.total_invested = load_all()

# --- 3. TAUX DE CHANGE (USD/EUR) ---
@st.cache_data(ttl=3600)
def get_exchange_rate():
    try:
        data = yf.download("EURUSD=X", period="1d", progress=False)
        valeur = data['Close'].iloc[-1]
        return float(valeur) if not isinstance(valeur, pd.Series) else float(valeur.iloc[0])
    except:
        return 1.08

rate = get_exchange_rate()
usd_eur_rate = 1.0 / rate

# --- 4. BARRE LATÉRALE ---
st.sidebar.header("⚙️ Configuration")

# Sauvegarde automatique : on détecte le changement de valeur
st.sidebar.subheader("💰 Gestion du Capital")
new_total_invested = st.sidebar.number_input("Montant Total Investi (€)", value=float(st.session_state.total_invested), step=100.0)
new_cash = st.sidebar.number_input("Montant Cash Actuel (€)", value=float(st.session_state.cash), step=100.0)

# Si les valeurs changent, on met à jour le state et on sauvegarde
if new_total_invested != st.session_state.total_invested or new_cash != st.session_state.cash:
    st.session_state.total_invested = new_total_invested
    st.session_state.cash = new_cash
    save_all()

# Ajout d'actions
st.sidebar.subheader("📈 Ajouter une Action")
with st.sidebar.form("add_form", clear_on_submit=True):
    t_input = st.text_input("Symbole (AAPL, MC.PA...)").upper()
    q_input = st.number_input("Quantité", min_value=0.0, step=0.01) # Step à 0.01 pour la précision
    p_input = st.number_input("Prix d'achat unitaire (devise native)", min_value=0.0)
    if st.form_submit_button("Ajouter position"):
        if t_input:
            new_line = pd.DataFrame({'Ticker': [t_input], 'Quantité': [q_input], 'Prix Achat ($ ou €)': [p_input]})
            st.session_state.portfolio = pd.concat([st.session_state.portfolio, new_line], ignore_index=True)
            save_all()
            st.rerun()

# Suppression
if not st.session_state.portfolio.empty:
    st.sidebar.subheader("🗑️ Gestion des lignes")
    idx_del = st.sidebar.selectbox("Ligne à supprimer", options=st.session_state.portfolio.index,
                                  format_func=lambda x: f"{st.session_state.portfolio.iloc[x]['Ticker']}")
    if st.sidebar.button("Supprimer la ligne"):
        st.session_state.portfolio = st.session_state.portfolio.drop(idx_del).reset_index(drop=True)
        save_all()
        st.rerun()

# --- 5. CALCULS ---
st.title("📊 Tableau de Bord Portefeuille")

if not st.session_state.portfolio.empty:
    # Récupération prix en temps réel
    tickers = st.session_state.portfolio['Ticker'].unique().tolist()
    prices_raw = yf.download(tickers, period="1d", progress=False)['Close']
    
    if isinstance(prices_raw, pd.Series):
        prices_df = prices_raw.to_frame()
        prices_df.columns = tickers
    else:
        prices_df = prices_raw
    last_prices = prices_df.iloc[-1].to_dict()

    # Dataframe de travail avec TRI ALPHABÉTIQUE
    df = st.session_state.portfolio.copy()
    df = df.sort_values(by='Ticker')
    
    df['Prix Actuel (Native)'] = df['Ticker'].map(last_prices)
    df['Devise'] = df['Ticker'].apply(lambda x: 'EUR' if x.endswith('.PA') else 'USD')
    
    def to_eur(row, col):
        return row[col] * usd_eur_rate if row['Devise'] == 'USD' else row[col]

    df['Prix Achat (€)'] = df.apply(lambda r: to_eur(r, 'Prix Achat ($ ou €)'), axis=1)
    df['Prix Actuel (€)'] = df.apply(lambda r: to_eur(r, 'Prix Actuel (Native)'), axis=1)
    df['Valeur Actuelle (€)'] = df['Quantité'] * df['Prix Actuel (€)']
    df['Plus-value (€)'] = (df['Prix Actuel (€)'] - df['Prix Achat (€)']) * df['Quantité']
    df['Perf %'] = ((df['Prix Actuel (€)'] - df['Prix Achat (€)']) / df['Prix Achat (€)']) * 100

    # CALCULS DES MÉTRIQUES GLOBALES
    valeur_actions = df['Valeur Actuelle (€)'].sum()
    valeur_pf_actuelle = valeur_actions + st.session_state.cash
    plus_value_totale_pf = valeur_pf_actuelle - st.session_state.total_invested
    roi_total_pct = (plus_value_totale_pf / st.session_state.total_invested * 100) if st.session_state.total_invested != 0 else 0

    # Affichage des métriques
    m1, m2, m3 = st.columns(3)
    m1.metric("Valeur PF Actuelle", f"{valeur_pf_actuelle:,.2f} €")
    m2.metric("Plus-Value Totale (P&L)", f"{plus_value_totale_pf:,.2f} €", f"{roi_total_pct:.2f}%")
    m3.metric("Cash Actuel", f"{st.session_state.cash:,.2f} €")

    # --- 6. TABLEAU ---
    st.subheader("📝 Détails des positions")
    cols = ['Ticker', 'Devise', 'Quantité', 'Prix Achat ($ ou €)', 'Prix Actuel (Native)', 'Valeur Actuelle (€)', 'Plus-value (€)', 'Perf %']
    
    def color_pnl(v):
        if v > 0.01: return 'color: #28a745; font-weight: bold'
        if v < -0.01: return 'color: #dc3545; font-weight: bold'
        return 'color: #6c757d'

    # Ligne Cash en haut
    cash_row = pd.DataFrame({
        'Ticker': ['💰 CASH'], 'Devise': ['EUR'], 'Quantité': [1.0], 'Prix Achat ($ ou €)': [None],
        'Prix Actuel (Native)': [None], 'Valeur Actuelle (€)': [st.session_state.cash], 'Plus-value (€)': [0.0], 'Perf %': [0.0]
    })
    display_df = pd.concat([cash_row, df], ignore_index=True)

    st.dataframe(
        display_df[cols].style.format({
            'Quantité': '{:.2f}', # <-- MODIFICATION ICI (2 décimales)
            'Prix Achat ($ ou €)': '{:,.2f}', 
            'Prix Actuel (Native)': '{:,.2f}',
            'Valeur Actuelle (€)': '{:,.2f} €', 
            'Plus-value (€)': '{:,.2f} €', 
            'Perf %': '{:.2f} %'
        }, na_rep="-").map(color_pnl, subset=['Plus-value (€)', 'Perf %']),
        use_container_width=True, hide_index=True
    )

    # --- 7. GRAPHES ---
    st.markdown("---")
    
    row1_c1, row1_c2 = st.columns(2)
    with row1_c1:
        st.subheader("1. Répartition du Portefeuille (€)")
        st.plotly_chart(px.pie(display_df, names='Ticker', values='Valeur Actuelle (€)', hole=0.4), use_container_width=True)
    with row1_c2:
        st.subheader("2. Performance Individuelle par Action (€)")
        st.plotly_chart(px.bar(df, x='Ticker', y='Plus-value (€)', color='Plus-value (€)', color_continuous_scale='RdYlGn'), use_container_width=True)

    row2_c1, row2_c2 = st.columns(2)
    with row2_c1:
        st.subheader("3. Comparaison Prix Achat vs Prix Marché")
        fig3 = go.Figure()
        fig3.add_trace(go.Scatter(x=df['Ticker'], y=df['Prix Achat (€)'], name="Prix Achat", mode='lines+markers', line=dict(color='red', width=3)))
        fig3.add_trace(go.Scatter(x=df['Ticker'], y=df['Prix Actuel (€)'], name="Prix Marché", mode='lines+markers', line=dict(color='green', width=3)))
        st.plotly_chart(fig3, use_container_width=True)
    with row2_c2:
        st.subheader("4. Montant Investi vs ROI Total (€)")
        labels4 = ['Capital Investi (€)', 'Plus-value Totale (€)']
        
        if plus_value_totale_pf >= 0:
            values4 = [st.session_state.total_invested, plus_value_totale_pf]
            colors4 = ['#3498db', '#2ecc71']
        else:
            labels4 = ['Valeur PF Restante (€)', 'Perte (€)']
            values4 = [valeur_pf_actuelle, abs(plus_value_totale_pf)]
            colors4 = ['#3498db', '#e74c3c']

        st.plotly_chart(px.pie(names=labels4, values=values4, color=labels4, color_discrete_map={labels4[0]:colors4[0], labels4[1]:colors4[1]}), use_container_width=True)

else:
    st.info(f"Portefeuille vide. Montant Investi : {st.session_state.total_invested:,.2f} € | Cash : {st.session_state.cash:,.2f} €")