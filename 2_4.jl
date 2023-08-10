using Gurobi,JuMP
using Plots, Random, Printf, XLSX, CSV, DataFrames, Distributions, MathOptInterface

# SETS and DATA

GEN_S=["S1","S2","S3","S4"]                  # price MAKER generators
GEN_O=["O1","O2","O3","O4"]                  # price TAKER generators
DEMAND=["D1","D2","D3","D4"]                 # demand
NODE=["N1","N2","N3","N4","N5","N6"]         # nodes

S=length(GEN_S)
O=length(GEN_O)
D=length(DEMAND)
N=length(NODE)
# X=length(SCENARIOS_TOT)

# SCENARIOS

SCENARIOS_TOT = String[]
for i in 1:1000
    push!(SCENARIOS_TOT, "S" * string(i))
end

X=length(SCENARIOS_TOT)

WIND_SCENARIO=["WQ1","WQ2","WQ3","WQ4","WQ5","WQ6","WQ7","WQ8"]   
NON_STRATEGIC_PRICE=["OP1","OP2","OP3","OP4","OP5"]
DEMAND_PRICE=["DP1","DP2","DP3","DP4","DP5"]
DEMAND_QUANTITY=["DQ1","DQ2","DQ3","DQ4","DQ5"]

w_q=[0 0.2 0.4 0.6 0.8 1 1.2 1.33]    # wind quantity
d_q=[0.2 0.5 0.9 1 1.08]              # demand quantity
d_p=[0.7 0.8 1 1.2 1.3]               # nonstrategic production cost
o_p=[0.7 0.8 1 1.2 1.3]               # demand bid price


WQ=length(w_q)   # wind quantity
DQ=length(d_q)   # demand quantity
OP=length(o_p)   # nonstrategic production cost
DP=length(d_p)   # demand bid price

scenarioz_coefficient=zeros(4,X)

global iiind=1

for wq = 1:WQ
    for dq = 1:DQ
        for op = 1:OP
            for dp = 1:DP
            scenarioz_coefficient[:,iiind] = [w_q[wq]; d_q[dq]; o_p[op]; d_p[dp]] 
            global iiind += 1 
            end
        end
    end
end

Y=100                            # in_sample scenarios
W=X-Y                            # out_sample scenarios

sY=zeros(Y)
scenarios_Y_coeff=zeros(4,Y)


Random.seed!(1234)
sY = sort(randperm(X)[1:Y])

global hh=1

for y=1:Y
    o=sY[y]
    scenarios_Y_coeff[:,hh]=scenarioz_coefficient[:,o]
global hh=hh+1
end

prob=1/Y

wind_x=1     # referring to the scenario, these are index names which refer to what coefficient I will be using 
dem_x=2
ooo_p=3
dem_p=4


# PREVIOUS DATA


D_Location=[3 4 5 6]    # demand location
S_Location=[1 2 3 6]    # price MAKER generators locations
O_Location=[1 2 3 5]    # price TAKER generators locations

D_quantity=[200 400 300 250]       # MW             ############################
D_quantity_Y=zeros(D,Y)
for d=1:D
    for y=1:Y
        D_quantity_Y[d,y]= D_quantity[d]*scenarios_Y_coeff[dem_x,y]
    end
end


D_bid_price=[26.5 24.7 23.1 22.5]    # euro/MWh     ############################
D_bid_price_Y=zeros(D,Y)
for d=1:D
    for y=1:Y
        D_bid_price_Y[d,y]= D_bid_price[d]*scenarios_Y_coeff[dem_p,y]
    end
end


S_capacity=[155 100 155 197]     # MW
S_cost=[15.2 23.4 15.2 19.1]     # euro/MWh



O_capacity=[0.75*450 350 210 80]      # MW        #############################
O_capacity_Y=zeros(O,Y)
for o=1:O
    for y=1:Y
    if o==1
        O_capacity_Y[o,y]= O_capacity[o]*scenarios_Y_coeff[wind_x,y]
    else
        O_capacity_Y[o,y]= O_capacity[o]
    end
end
end


O_cost=[0 5 20.1 24.7]           # euro/MWh        ############################
O_cost_Y=zeros(O,Y)
for o=1:O
    for y=1:Y
        O_cost_Y[o,y]= O_cost[o]*scenarios_Y_coeff[ooo_p,y]
    end
end

S_ramp=[90 85 90 120]    # MW/h
O_ramp=[0 350 170 80]    # MW/h

susceptance=50
BB=1/susceptance

Big_M = 10^4


# OPTIMIZATION MODEL - VARIABLE

TWO_FOUR= Model(Gurobi.Optimizer)

@variable(TWO_FOUR, S_prod[1:S,1:Y])
@variable(TWO_FOUR, O_prod[1:O,1:Y])

@variable(TWO_FOUR, lambda[1:Y])

@variable(TWO_FOUR, S_alpha_offer[1:S])
@variable(TWO_FOUR, demand[1:D,1:Y])

@variable(TWO_FOUR, mu_D_up[1:D,1:Y])
@variable(TWO_FOUR, mu_D_down[1:D,1:Y])

@variable(TWO_FOUR, mu_O_up[1:O,1:Y])
@variable(TWO_FOUR, mu_O_down[1:O,1:Y])

@variable(TWO_FOUR, mu_S_up[1:S,1:Y])
@variable(TWO_FOUR, mu_S_down[1:S,1:Y])

@variable(TWO_FOUR, epsi_D_up[1:D,1:Y],Bin)                                                     # 11
@variable(TWO_FOUR, epsi_D_down[1:D,1:Y],Bin)                                                   # 16

@variable(TWO_FOUR, epsi_O_up[1:O,1:Y],Bin)                                                     # 21
@variable(TWO_FOUR, epsi_O_down[1:O,1:Y],Bin)                                                   # 26

@variable(TWO_FOUR, epsi_S_up[1:S,1:Y], Bin)                                                    # 31
@variable(TWO_FOUR, epsi_S_down[1:S,1:Y], Bin)                                                  # 36


# GENERAL CONSTRAINTS

#@constraint(TWO_FOUR,[s=1:S], S_alpha_offer[s] >= S_cost[s])                                 # 1
@constraint(TWO_FOUR,[s=1:S], S_alpha_offer[s]>=0)                                            # 2
@constraint(TWO_FOUR,[d=1:D,y=1:Y], - D_bid_price_Y[d,y] + mu_D_up[d,y] - mu_D_down[d,y] + lambda[y] == 0)     # 3
@constraint(TWO_FOUR,[s=1:S,y=1:Y], S_alpha_offer[s] + mu_S_up[s,y] - mu_S_down[s,y] - lambda[y] == 0)     # 4
@constraint(TWO_FOUR,[o=1:O,y=1:Y], O_cost_Y[o,y] + mu_O_up[o,y] - mu_O_down[o,y] - lambda[y] == 0)            # 5
@constraint(TWO_FOUR,[y=1:Y], sum(demand[d,y] for d=1:D) - sum(S_prod[s,y] for s=1:S) - sum(O_prod[o,y] for o=1:O) == 0) # 6 power balance  ###########

# DEMAND

@constraint(TWO_FOUR, [d=1:D,y=1:Y], demand[d,y]<=D_quantity_Y[d,y])                                     # 7
@constraint(TWO_FOUR,[d=1:D,y=1:Y], mu_D_up[d,y]>=0)                                                 # 8
@constraint(TWO_FOUR, [d=1:D,y=1:Y], D_quantity_Y[d,y] - demand[d,y] <= epsi_D_up[d,y]*Big_M)              # 9
@constraint(TWO_FOUR,[d=1:D,y=1:Y], mu_D_up[d,y] <= (1 - epsi_D_up[d,y])*Big_M)                        # 10
# 11 is in the variable
@constraint(TWO_FOUR,[d=1:D,y=1:Y], demand[d,y] >= 0)                                                # 12
@constraint(TWO_FOUR,[d=1:D,y=1:Y], mu_D_down[d,y] >= 0)                                             # 13
@constraint(TWO_FOUR,[d=1:D,y=1:Y], demand[d,y] <= epsi_D_down[d,y]*Big_M)                             # 14
@constraint(TWO_FOUR,[d=1:D,y=1:Y], mu_D_down[d,y] <= (1 - epsi_D_down[d,y])*Big_M)                    # 15
# 16 is in the variable

# PRICE MAKER - LEADER - S

@constraint(TWO_FOUR, [s=1:S,y=1:Y], S_prod[s,y]<=S_capacity[s])                                     # 17
@constraint(TWO_FOUR,[s=1:S,y=1:Y], mu_S_up[s,y]>=0)                                                 # 18
@constraint(TWO_FOUR, [s=1:S,y=1:Y], S_capacity[s] - S_prod[s,y] <= epsi_S_up[s,y]*Big_M)              # 19
@constraint(TWO_FOUR,[s=1:S,y=1:Y], mu_S_up[s,y] <= (1 - epsi_S_up[s,y])*Big_M)                        # 20
# 21 is in the variable
@constraint(TWO_FOUR,[s=1:S,y=1:Y], S_prod[s,y] >= 0)                                                # 22
@constraint(TWO_FOUR,[s=1:S,y=1:Y], mu_S_down[s,y] >= 0)                                             # 23
@constraint(TWO_FOUR,[s=1:S,y=1:Y], S_prod[s,y] <= epsi_S_down[s,y]*Big_M)                             # 24
@constraint(TWO_FOUR,[s=1:S,y=1:Y], mu_S_down[s,y] <= (1 - epsi_S_down[s,y])*Big_M)                    # 25
# 26 is in the variable

# PRICE TAKER - FOLLOWERS - O

@constraint(TWO_FOUR, [o=1:O,y=1:Y], O_prod[o,y]<=O_capacity_Y[o,y])                                     # 27
@constraint(TWO_FOUR,[o=1:O,y=1:Y], mu_O_up[o,y]>=0)                                                 # 28
@constraint(TWO_FOUR, [o=1:O,y=1:Y], O_capacity_Y[o,y] - O_prod[o,y] <= epsi_O_up[o,y]*Big_M)              # 29
@constraint(TWO_FOUR,[o=1:O,y=1:Y], mu_O_up[o,y] <= (1 - epsi_O_up[o,y])*Big_M)                        # 30
# 31 is in the variable
@constraint(TWO_FOUR,[o=1:O,y=1:Y], O_prod[o,y] >= 0)                                                # 32
@constraint(TWO_FOUR,[o=1:O,y=1:Y], mu_O_down[o,y] >= 0)                                             # 33
@constraint(TWO_FOUR,[o=1:O,y=1:Y], O_prod[o,y] <= epsi_O_down[o,y]*Big_M)                             # 34
@constraint(TWO_FOUR,[o=1:S,y=1:Y], mu_O_down[o,y] <= (1 - epsi_O_down[o,y])*Big_M)                    # 35
# 36 is in the variable

@objective(TWO_FOUR, Max, sum(prob*(- sum(S_prod[s,y]*S_cost[s] for s=1:S) 
                         + sum(D_bid_price_Y[d,y]*demand[d,y] for d=1:D)
                         - sum(O_cost_Y[o,y]*O_prod[o,y] for o=1:O)
                         - sum(mu_D_up[d,y]*D_quantity_Y[d,y] for d=1:D)
                         - sum(mu_O_up[o,y]*O_capacity_Y[o,y] for o=1:O)) for y=1:Y)
)


optimize!(TWO_FOUR)

for s=1:S
    println("Offer Price ", GEN_S[s], @sprintf(" %.2f \$" , value(S_alpha_offer[s]))," - Production cost: ", @sprintf(" %.2f \$" , S_cost[s]))
end 


println("\n")
for y=1:Y
    x=sY[y]
println("Market clearing price at scenario ",SCENARIOS_TOT[x], @sprintf(": %.2f \$" , value(lambda[y])))
end








# FEASIBILITY DATA TEST

global tot_cap_min=w_q[1]*O_capacity[1]
global tot_cap_min = tot_cap_min + sum(O_capacity[o] for o=2:O) + sum(S_capacity[s] for s=1:S)

global tot_dem_max=0
for d=1:D
           global tot_dem_max = tot_dem_max + D_quantity[d]*d_q[DQ]
end

feasibility_test = tot_cap_min - tot_dem_max

println("\n")
println("Feasibility data test:", @sprintf(" %.2f MW more of total capacity - " , feasibility_test), "min tot production: ", @sprintf(" %.2f MW " , tot_cap_min), " - max tot demand: ", @sprintf(" %.2f MW " , tot_dem_max) )

