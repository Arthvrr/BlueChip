import yfinance as yf
from currency_converter import CurrencyConverter

tickers = ["ASML","GOOGL","MA","MSFT","NVDA","V"]
shares = [6,20,4,8,15,10]
pru = [689.615,166.19625,411.67375,364.5375,188.105,274.796]
cash = 1108.48

def get_current_price(tickers):
    """
    Retourne une liste des prix actuels pour chaque ticker sous forme de float classique.
    """
    prices = []
    for t in tickers:
        data = yf.Ticker(t).history(period="1d")
        price = float(data["Close"].iloc[-1])  # conversion en float Python
        prices.append(round(price, 2))
    return prices

def get_total_value(prices, shares):
    """
    Calcule la valeur totale du portefeuille.
    """
    total = (sum(p * s for p, s in zip(prices, shares)) * get_currency_usd_eur()) + cash
    return round(total, 2)

def get_stocks_values(prices,shares):
    """
    Calcule la valeur totale de chaque action.
    """
    total_value = []
    for i in range(len(prices)):
        temp_val = round((prices[i] * shares[i]) * get_currency_usd_eur(),2)
        total_value.append(temp_val)
    return total_value

def get_currency_usd_eur():
    """
    Retourne le taux de change d'un dollar en euro
    """
    c = CurrencyConverter()
    return round(c.convert(1, 'USD', 'EUR'), 2)




#appels des fonctions
get_currency_usd_eur()
currentPrice = get_current_price(tickers)
walletValue = get_total_value(currentPrice, shares)
stocksValue = get_stocks_values(currentPrice,shares)

print("Prix actuels :", currentPrice)
print("Valeur totale du portefeuille :", walletValue)
print(stocksValue)
print(get_currency_usd_eur())